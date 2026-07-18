#!/bin/bash

APP_URL="http://localhost:3000/health"
MAX_RETRY=5
RETRY_DELAY=3

# Pendekatan 1: Pemeriksaan status proses PM2
PM2_STATUS=$(pm2 jlist | grep -o '"status":"online"' | head -1)
if [ -z "$PM2_STATUS" ]; then
  echo "[HEALTH CHECK] Proses PM2 tidak berstatus online"
  exit 1
fi

# Pendekatan 2: Pemeriksaan HTTP endpoint /health
for i in $(seq 1 $MAX_RETRY); do
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" $APP_URL)
  if [ "$HTTP_CODE" -eq 200 ]; then
    echo "[HEALTH CHECK] Berhasil, HTTP $HTTP_CODE diterima"
    exit 0
  fi
  echo "[HEALTH CHECK] Percobaan $i gagal (HTTP $HTTP_CODE), mencoba lagi..."
  sleep $RETRY_DELAY
done

echo "[HEALTH CHECK] Gagal setelah $MAX_RETRY percobaan"
exit 1

