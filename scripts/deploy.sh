#!/bin/bash
set -e

APP_DIR="/home/ubuntu/app"
NEW_DIR="/home/ubuntu/app_new"
BACKUP_DIR="/home/ubuntu/backup/app_$(date +%Y%m%d_%H%M%S)"
LOG_FILE="/home/ubuntu/logs/deploy.log"

echo "[$(date)] === Memulai proses deployment ===" >> $LOG_FILE

# ===== FASE 1: PERSIAPAN (Pre-deployment) =====
echo "[FASE 1] Membuat backup versi sebelumnya..." >> $LOG_FILE
mkdir -p $BACKUP_DIR
if [ -d "$APP_DIR" ]; then
  cp -r $APP_DIR/* $BACKUP_DIR/ 2>/dev/null || true
fi

# ===== FASE 2: PEMBARUAN (Update) =====
echo "[FASE 2] Mengganti berkas aplikasi dengan versi terbaru..." >> $LOG_FILE
mkdir -p $APP_DIR
cp -r $NEW_DIR/* $APP_DIR/
cd $APP_DIR
npm install --production

# ===== FASE 3: PEMULIHAN (Post-deployment) =====
echo "[FASE 3] Melakukan graceful restart via PM2..." >> $LOG_FILE
pm2 reload app-server --update-env || pm2 start src/server.js --name app-server
sleep 5

# Health check otomatis (lihat scripts/healthcheck.sh)
bash /home/ubuntu/app/scripts/healthcheck.sh
if [ $? -ne 0 ]; then
  echo "[ERROR] Health check gagal. Menjalankan rollback..." >> $LOG_FILE
  cp -r $BACKUP_DIR/* $APP_DIR/
  pm2 reload app-server --update-env
  echo "[ROLLBACK] Versi sebelumnya berhasil dipulihkan." >> $LOG_FILE
  exit 1
fi

echo "[$(date)] === Deployment berhasil ===" >> $LOG_FILE
rm -rf $NEW_DIR

