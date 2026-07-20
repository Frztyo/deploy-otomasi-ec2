#!/bin/bash
# =============================================================================
# deploy.sh — Skrip Deploy Otomasi Minimal Downtime untuk React (Vite) di EC2
# Strategi: Build → Backup → Swap → Health Check → Rollback jika gagal
# =============================================================================
set -e

# ── Konfigurasi path ──────────────────────────────────────────────────────
APP_DIR="/var/www/stressmeter"            # Direktori nginx serve
BUILD_SRC="/home/ubuntu/app/dist"         # Hasil build Vite
BACKUP_DIR="/home/ubuntu/backup/app_$(date +%Y%m%d_%H%M%S)"
LOG_FILE="/home/ubuntu/logs/deploy.log"
REPO_DIR="/home/ubuntu/app"              # Direktori repo hasil git pull

# Pastikan direktori log ada
mkdir -p "$(dirname $LOG_FILE)"
mkdir -p "$BACKUP_DIR"
mkdir -p "$APP_DIR"

echo "[$(date)] === Memulai proses deployment (React/Vite) ===" >> $LOG_FILE

# ─────────────────────────────────────────────────────────────────────────────
# FASE 1: PERSIAPAN — Backup versi yang sedang berjalan
# ─────────────────────────────────────────────────────────────────────────────
echo "[FASE 1] Membuat backup versi sebelumnya ke $BACKUP_DIR..." >> $LOG_FILE
if [ -d "$APP_DIR" ] && [ "$(ls -A $APP_DIR)" ]; then
  cp -r "$APP_DIR"/. "$BACKUP_DIR/"
  echo "[FASE 1] Backup selesai." >> $LOG_FILE
else
  echo "[FASE 1] Tidak ada file untuk di-backup (deployment pertama)." >> $LOG_FILE
fi

# ─────────────────────────────────────────────────────────────────────────────
# FASE 2: BUILD — Install dependencies dan build React dengan Vite
# ─────────────────────────────────────────────────────────────────────────────
echo "[FASE 2] Menjalankan npm install dan npm run build..." >> $LOG_FILE
cd "$REPO_DIR"
npm install >> $LOG_FILE 2>&1
npm run build >> $LOG_FILE 2>&1
echo "[FASE 2] Build React selesai. Output: $BUILD_SRC" >> $LOG_FILE

# ─────────────────────────────────────────────────────────────────────────────
# FASE 3: SWAP — Salin hasil build ke direktori nginx
# ─────────────────────────────────────────────────────────────────────────────
echo "[FASE 3] Menyalin dist/ ke $APP_DIR..." >> $LOG_FILE
rm -rf "$APP_DIR"/*
cp -r "$BUILD_SRC"/. "$APP_DIR/"
echo "[FASE 3] File berhasil disalin." >> $LOG_FILE

# ─────────────────────────────────────────────────────────────────────────────
# FASE 4: RELOAD NGINX — Agar file baru langsung serve
# ─────────────────────────────────────────────────────────────────────────────
echo "[FASE 4] Mereload nginx..." >> $LOG_FILE
sudo nginx -t >> $LOG_FILE 2>&1 && sudo systemctl reload nginx
echo "[FASE 4] Nginx berhasil direload." >> $LOG_FILE

# ─────────────────────────────────────────────────────────────────────────────
# FASE 5: HEALTH CHECK — Pastikan halaman bisa diakses
# ─────────────────────────────────────────────────────────────────────────────
echo "[FASE 5] Menjalankan health check..." >> $LOG_FILE
bash "$REPO_DIR/scripts/healthcheck.sh"
if [ $? -ne 0 ]; then
  echo "[ERROR] Health check gagal. Menjalankan rollback..." >> $LOG_FILE

  # Rollback: kembalikan file backup
  rm -rf "$APP_DIR"/*
  if [ "$(ls -A $BACKUP_DIR)" ]; then
    cp -r "$BACKUP_DIR"/. "$APP_DIR/"
    sudo systemctl reload nginx
    echo "[ROLLBACK] Versi sebelumnya berhasil dipulihkan dari $BACKUP_DIR." >> $LOG_FILE
  else
    echo "[ROLLBACK] Tidak ada backup untuk dipulihkan." >> $LOG_FILE
  fi
  exit 1
fi

echo "[$(date)] === Deployment React berhasil ===" >> $LOG_FILE
