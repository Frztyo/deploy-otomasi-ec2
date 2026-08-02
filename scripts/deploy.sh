#!/bin/bash
# =============================================================================
# deploy.sh — Skrip Deploy Otomasi Minimal Downtime untuk React (Vite) di EC2
# Strategi: Sync → Backup → Build → Swap → Reload Nginx → Health Check → Rollback
# Fitur: Pencatatan waktu per-fase dan total waktu deployment
# =============================================================================
set -e

# ── Konfigurasi path ──────────────────────────────────────────────────────────
APP_DIR="/var/www/stressmeter"                        # Direktori web root Nginx
BUILD_SRC="/home/ubuntu/app/src/dist"                 # Output build Vite
BACKUP_DIR="/home/ubuntu/backup/app_$(date +%Y%m%d_%H%M%S)"
LOG_FILE="/home/ubuntu/logs/deploy.log"               # Log detail per-fase
RECORD_FILE="/home/ubuntu/logs/deploy_record.log"     # Rekaman ringkasan waktu deployment
REPO_DIR="/home/ubuntu/app"                           # Direktori kerja repositori
NEW_DIR="/home/ubuntu/app_new"                        # Direktori penampung SCP dari GitHub Actions

# Ambil info commit dari file yang dikirim GitHub Actions (jika ada)
COMMIT_SHA="${GITHUB_SHA:-$(cat $NEW_DIR/.commit_sha 2>/dev/null || echo 'unknown')}"
COMMIT_MSG="${GITHUB_COMMIT_MSG:-$(cat $NEW_DIR/.commit_msg 2>/dev/null || echo 'unknown')}"
BRANCH="${GITHUB_REF_NAME:-main}"

# ── Inisialisasi direktori & file ─────────────────────────────────────────────
mkdir -p "$(dirname $LOG_FILE)"
mkdir -p "$BACKUP_DIR"
mkdir -p "$APP_DIR"

# Catat waktu mulai keseluruhan deployment
DEPLOY_START=$(date +%s)
DEPLOY_START_READABLE=$(date "+%Y-%m-%d %H:%M:%S")

echo "" >> $LOG_FILE
echo "============================================================" >> $LOG_FILE
echo "[$(date '+%Y-%m-%d %H:%M:%S')] DEPLOYMENT DIMULAI" >> $LOG_FILE
echo "  Branch  : $BRANCH" >> $LOG_FILE
echo "  Commit  : $COMMIT_SHA" >> $LOG_FILE
echo "  Pesan   : $COMMIT_MSG" >> $LOG_FILE
echo "============================================================" >> $LOG_FILE

# ─────────────────────────────────────────────────────────────────────────────
# FASE 1: SINKRONISASI — Salin kode baru dari folder penampung SCP
# ─────────────────────────────────────────────────────────────────────────────
FASE1_START=$(date +%s)
echo "[$(date '+%H:%M:%S')] [FASE 1] Menyinkronkan kode dari $NEW_DIR ke $REPO_DIR ..." >> $LOG_FILE

mkdir -p "$REPO_DIR"
rsync -a --delete \
  --exclude 'node_modules' \
  --exclude 'dist' \
  --exclude '.git' \
  "$NEW_DIR/" "$REPO_DIR/"

FASE1_END=$(date +%s)
FASE1_DURATION=$((FASE1_END - FASE1_START))
echo "[$(date '+%H:%M:%S')] [FASE 1] Sinkronisasi selesai. (${FASE1_DURATION}s)" >> $LOG_FILE

# ─────────────────────────────────────────────────────────────────────────────
# FASE 2: BACKUP — Cadangkan versi produksi yang sedang berjalan
# ─────────────────────────────────────────────────────────────────────────────
FASE2_START=$(date +%s)
echo "[$(date '+%H:%M:%S')] [FASE 2] Membuat backup versi aktif ke $BACKUP_DIR ..." >> $LOG_FILE

if [ -d "$APP_DIR" ] && [ "$(ls -A $APP_DIR 2>/dev/null)" ]; then
  cp -r "$APP_DIR"/. "$BACKUP_DIR/"
  echo "[$(date '+%H:%M:%S')] [FASE 2] Backup selesai." >> $LOG_FILE
else
  echo "[$(date '+%H:%M:%S')] [FASE 2] Tidak ada file untuk di-backup (deployment pertama)." >> $LOG_FILE
fi

FASE2_END=$(date +%s)
FASE2_DURATION=$((FASE2_END - FASE2_START))
echo "[$(date '+%H:%M:%S')] [FASE 2] Backup selesai. (${FASE2_DURATION}s)" >> $LOG_FILE

# ─────────────────────────────────────────────────────────────────────────────
# FASE 3: BUILD — Install dependensi dan kompilasi React dengan Vite
# ─────────────────────────────────────────────────────────────────────────────
FASE3_START=$(date +%s)
echo "[$(date '+%H:%M:%S')] [FASE 3] Menjalankan npm install --prefix src ..." >> $LOG_FILE

cd "$REPO_DIR"
npm install --prefix src >> $LOG_FILE 2>&1

echo "[$(date '+%H:%M:%S')] [FASE 3] Menjalankan npm run build ..." >> $LOG_FILE
npm run build >> $LOG_FILE 2>&1

FASE3_END=$(date +%s)
FASE3_DURATION=$((FASE3_END - FASE3_START))
echo "[$(date '+%H:%M:%S')] [FASE 3] Build selesai. Output: $BUILD_SRC (${FASE3_DURATION}s)" >> $LOG_FILE

# ─────────────────────────────────────────────────────────────────────────────
# FASE 4: SWAP — Salin hasil build ke direktori Nginx
# ─────────────────────────────────────────────────────────────────────────────
FASE4_START=$(date +%s)
echo "[$(date '+%H:%M:%S')] [FASE 4] Menyalin dist/ ke $APP_DIR ..." >> $LOG_FILE

sudo rm -rf "$APP_DIR"/*
sudo cp -r "$BUILD_SRC"/. "$APP_DIR/"
sudo chown -R www-data:www-data "$APP_DIR"
sudo find "$APP_DIR" -type d -exec chmod 755 {} \;
sudo find "$APP_DIR" -type f -exec chmod 644 {} \;

FASE4_END=$(date +%s)
FASE4_DURATION=$((FASE4_END - FASE4_START))
echo "[$(date '+%H:%M:%S')] [FASE 4] File berhasil disalin dan permission diatur. (${FASE4_DURATION}s)" >> $LOG_FILE

# ─────────────────────────────────────────────────────────────────────────────
# FASE 5: RELOAD NGINX — Terapkan perubahan tanpa downtime
# ─────────────────────────────────────────────────────────────────────────────
FASE5_START=$(date +%s)
echo "[$(date '+%H:%M:%S')] [FASE 5] Memvalidasi konfigurasi dan mereload Nginx ..." >> $LOG_FILE

sudo nginx -t >> $LOG_FILE 2>&1 && sudo systemctl reload nginx

FASE5_END=$(date +%s)
FASE5_DURATION=$((FASE5_END - FASE5_START))
echo "[$(date '+%H:%M:%S')] [FASE 5] Nginx berhasil direload. (${FASE5_DURATION}s)" >> $LOG_FILE

# ─────────────────────────────────────────────────────────────────────────────
# FASE 6: HEALTH CHECK — Verifikasi layanan berjalan normal
# ─────────────────────────────────────────────────────────────────────────────
FASE6_START=$(date +%s)
echo "[$(date '+%H:%M:%S')] [FASE 6] Menjalankan health check ..." >> $LOG_FILE

bash "$REPO_DIR/scripts/healthcheck.sh" >> $LOG_FILE 2>&1
HEALTH_STATUS=$?

FASE6_END=$(date +%s)
FASE6_DURATION=$((FASE6_END - FASE6_START))

if [ $HEALTH_STATUS -ne 0 ]; then
  echo "[$(date '+%H:%M:%S')] [ERROR] Health check gagal! (${FASE6_DURATION}s)" >> $LOG_FILE
  echo "[$(date '+%H:%M:%S')] [ROLLBACK] Mengembalikan ke versi sebelumnya ..." >> $LOG_FILE

  sudo rm -rf "$APP_DIR"/*
  if [ -d "$BACKUP_DIR" ] && [ "$(ls -A $BACKUP_DIR 2>/dev/null)" ]; then
    sudo cp -r "$BACKUP_DIR"/. "$APP_DIR/"
    sudo systemctl reload nginx
    echo "[$(date '+%H:%M:%S')] [ROLLBACK] Versi sebelumnya berhasil dipulihkan dari $BACKUP_DIR." >> $LOG_FILE
  else
    echo "[$(date '+%H:%M:%S')] [ROLLBACK] Tidak ada backup yang tersedia." >> $LOG_FILE
  fi

  # Catat rekaman deployment GAGAL
  DEPLOY_END=$(date +%s)
  TOTAL_DURATION=$((DEPLOY_END - DEPLOY_START))
  echo "$(date '+%Y-%m-%d %H:%M:%S') | STATUS=GAGAL | BRANCH=$BRANCH | COMMIT=$COMMIT_SHA | TOTAL=${TOTAL_DURATION}s | F1=${FASE1_DURATION}s | F2=${FASE2_DURATION}s | F3=${FASE3_DURATION}s | F4=${FASE4_DURATION}s | F5=${FASE5_DURATION}s | F6=${FASE6_DURATION}s" >> $RECORD_FILE

  echo "============================================================" >> $LOG_FILE
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] DEPLOYMENT GAGAL - Total waktu: ${TOTAL_DURATION}s" >> $LOG_FILE
  echo "============================================================" >> $LOG_FILE
  exit 1
fi

echo "[$(date '+%H:%M:%S')] [FASE 6] Health check berhasil. (${FASE6_DURATION}s)" >> $LOG_FILE

# ─────────────────────────────────────────────────────────────────────────────
# SELESAI — Hitung dan catat total waktu deployment
# ─────────────────────────────────────────────────────────────────────────────
DEPLOY_END=$(date +%s)
TOTAL_DURATION=$((DEPLOY_END - DEPLOY_START))

# Tulis rekaman ringkasan ke deploy_record.log (untuk analisis efisiensi)
echo "$(date '+%Y-%m-%d %H:%M:%S') | STATUS=SUKSES | BRANCH=$BRANCH | COMMIT=$COMMIT_SHA | TOTAL=${TOTAL_DURATION}s | F1=${FASE1_DURATION}s | F2=${FASE2_DURATION}s | F3=${FASE3_DURATION}s | F4=${FASE4_DURATION}s | F5=${FASE5_DURATION}s | F6=${FASE6_DURATION}s" >> $RECORD_FILE

echo "============================================================" >> $LOG_FILE
echo "[$(date '+%Y-%m-%d %H:%M:%S')] DEPLOYMENT BERHASIL" >> $LOG_FILE
echo "  Total waktu  : ${TOTAL_DURATION} detik" >> $LOG_FILE
echo "  Rincian      :" >> $LOG_FILE
echo "    Fase 1 Sinkronisasi : ${FASE1_DURATION}s" >> $LOG_FILE
echo "    Fase 2 Backup       : ${FASE2_DURATION}s" >> $LOG_FILE
echo "    Fase 3 Build        : ${FASE3_DURATION}s" >> $LOG_FILE
echo "    Fase 4 Swap Berkas  : ${FASE4_DURATION}s" >> $LOG_FILE
echo "    Fase 5 Reload Nginx : ${FASE5_DURATION}s" >> $LOG_FILE
echo "    Fase 6 Health Check : ${FASE6_DURATION}s" >> $LOG_FILE
echo "============================================================" >> $LOG_FILE
