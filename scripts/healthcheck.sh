#!/bin/bash
# =============================================================================
# healthcheck.sh — Health check untuk aplikasi React yang diserve via Nginx
# =============================================================================

APP_URL="http://localhost"       
MAX_RETRY=5
RETRY_DELAY=3

echo "[HEALTH CHECK] Memeriksa aplikasi React di $APP_URL..."

# Pendekatan 1: Pastikan nginx berjalan
NGINX_STATUS=$(systemctl is-active nginx 2>/dev/null || echo "inactive")
if [ "$NGINX_STATUS" != "active" ]; then
  echo "[HEALTH CHECK] Nginx tidak aktif! Status: $NGINX_STATUS"
  exit 1
fi
echo "[HEALTH CHECK] Nginx aktif."

# Pendekatan 2: Periksa HTTP endpoint halaman utama
for i in $(seq 1 $MAX_RETRY); do
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$APP_URL")
  if [ "$HTTP_CODE" -eq 200 ]; then
    echo "[HEALTH CHECK] Berhasil! HTTP $HTTP_CODE diterima dari $APP_URL"
    exit 0
  fi
  echo "[HEALTH CHECK] Percobaan $i gagal (HTTP $HTTP_CODE), mencoba lagi dalam $RETRY_DELAY detik..."
  sleep $RETRY_DELAY
done

echo "[HEALTH CHECK] Gagal setelah $MAX_RETRY percobaan. HTTP terakhir: $HTTP_CODE"
exit 1
