# Laporan Perubahan Kode — Revisi Pipeline CI/CD

Dokumen ini mencatat **seluruh perubahan** yang dilakukan pada pipeline otomasi deployment proyek `deploy-otomasi-ec2` agar sinkron dengan implementasi di laporan Tugas Akhir, termasuk penambahan fitur pencatatan waktu deployment.

---

## Ringkasan Perubahan

| File | Status | Perubahan Utama |
|------|--------|----------------|
| `.github/workflows/deploy.yml` | ✅ Direvisi | Tambah timing CI, metadata commit, chmod healthcheck |
| `scripts/deploy.sh` | ✅ Direvisi | Tambah 6 fase terstruktur, timing per-fase, `deploy_record.log` |
| `scripts/healthcheck.sh` | ✅ Direvisi | Tambah pengukuran response time HTTP (ms) |

---

## 1. `.github/workflows/deploy.yml`

### Sebelum:
```yaml
      - name: Install dependencies dan build (tahap CI)
        run: |
          npm install
          npm run build --if-present

      - name: Transfer artefak ke EC2 (SCP)
        uses: appleboy/scp-action@v0.1.7
        with:
          source: "src/,package.json,scripts/"
          target: "/home/ubuntu/app_new"

      - name: Eksekusi skrip deployment (SSH)
        uses: appleboy/ssh-action@v1.0.3
        with:
          script: |
            chmod +x /home/ubuntu/app_new/scripts/deploy.sh
            /home/ubuntu/app_new/scripts/deploy.sh
```

### Sesudah:
```yaml
      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'                                  # BARU: cache npm
          cache-dependency-path: src/package-lock.json # BARU: path lock file

      - name: Catat waktu mulai CI          # BARU
        id: ci_start
        run: echo "ci_start=$(date +%s)" >> $GITHUB_OUTPUT

      - name: Install dependencies dan build (tahap CI)
        run: |
          npm install --prefix src           # DIUBAH: prefix src
          npm run build                      # DIUBAH: hapus --if-present

      - name: Catat waktu selesai CI        # BARU
        id: ci_end
        run: |
          CI_DURATION=$((CI_END - ci_start))
          echo "CI Build selesai dalam: ${CI_DURATION} detik"

      - name: Buat file metadata commit     # BARU
        run: |
          echo "${{ github.sha }}" > .commit_sha
          echo "${{ github.event.head_commit.message }}" > .commit_msg
          echo "CI_DURATION=...s" > .ci_info

      - name: Transfer artefak ke EC2 (SCP)
        with:
          source: "src/,package.json,scripts/,.commit_sha,.commit_msg,.ci_info"  # DIUBAH: tambah metadata
          target: "/home/ubuntu/app_new"

      - name: Eksekusi skrip deployment via SSH
        with:
          script: |
            chmod +x /home/ubuntu/app_new/scripts/deploy.sh
            chmod +x /home/ubuntu/app_new/scripts/healthcheck.sh  # BARU
            GITHUB_SHA="..." \              # BARU: kirim env vars ke server
            GITHUB_COMMIT_MSG="..." \
            GITHUB_REF_NAME="..." \
            /home/ubuntu/app_new/scripts/deploy.sh
```

### Alasan Perubahan:
| No | Perubahan | Alasan |
|----|-----------|--------|
| 1 | Tambah `cache: 'npm'` | Mempercepat pipeline dengan cache dependensi antar run |
| 2 | Tambah step pencatatan waktu CI | Mendapatkan durasi build untuk dicatat di laporan |
| 3 | Ubah `npm install` → `npm install --prefix src` | Dependensi React ada di `src/package.json`, bukan root |
| 4 | Buat file `.commit_sha`, `.commit_msg`, `.ci_info` | Informasi commit dikirim ke server untuk dicatat di log |
| 5 | Tambah metadata ke source SCP | File metadata ikut terkirim ke EC2 |
| 6 | Tambah `chmod +x healthcheck.sh` | Pastikan skrip health check dapat dieksekusi |
| 7 | Tambah env vars `GITHUB_SHA`, `GITHUB_COMMIT_MSG`, `GITHUB_REF_NAME` | Server bisa mencatat info commit di `deploy.log` dan `deploy_record.log` |

---

## 2. `scripts/deploy.sh`

### Perubahan Struktural (Fase Deployment):

| | Sebelum (4 Fase) | Sesudah (6 Fase) |
|-|------------------|------------------|
| Fase 1 | Backup | **Sinkronisasi** `app_new` → `app` |
| Fase 2 | Build | **Backup** versi produksi aktif |
| Fase 3 | Swap berkas | **Build** React (npm install + build) |
| Fase 4 | Reload + Health Check | **Swap** berkas build ke Nginx root |
| — | — | **Fase 5:** Reload Nginx |
| — | — | **Fase 6:** Health Check + Rollback |

### Fitur Baru yang Ditambahkan:

#### A. Pencatatan Waktu Per-Fase
```bash
# SEBELUM — tidak ada pengukuran waktu
echo "[FASE 2] Menjalankan npm install..." >> $LOG_FILE

# SESUDAH — setiap fase diukur waktunya
FASE3_START=$(date +%s)
echo "[$(date '+%H:%M:%S')] [FASE 3] Menjalankan npm install --prefix src ..." >> $LOG_FILE
npm install --prefix src >> $LOG_FILE 2>&1
FASE3_END=$(date +%s)
FASE3_DURATION=$((FASE3_END - FASE3_START))
echo "[$(date '+%H:%M:%S')] [FASE 3] Build selesai. (${FASE3_DURATION}s)" >> $LOG_FILE
```

#### B. File Rekaman Baru: `deploy_record.log`
```bash
# File baru: /home/ubuntu/logs/deploy_record.log
RECORD_FILE="/home/ubuntu/logs/deploy_record.log"

# Setiap deployment menulis 1 baris ringkasan:
# FORMAT:
# 2026-08-02 19:00:00 | STATUS=SUKSES | BRANCH=main | COMMIT=abc123 | TOTAL=71s | F1=2s | F2=1s | F3=55s | F4=3s | F5=1s | F6=9s
```

File ini berguna untuk **analisis perbandingan efisiensi deployment** antar waktu pada sub-bab 4.2.6.

#### C. Pencatatan Info Commit di Header Log
```bash
# SESUDAH — header log menyertakan info commit
echo "  Branch  : $BRANCH" >> $LOG_FILE
echo "  Commit  : $COMMIT_SHA" >> $LOG_FILE
echo "  Pesan   : $COMMIT_MSG" >> $LOG_FILE
```

#### D. Sinkronisasi `app_new` → `app` dengan rsync (Fase 1)
```bash
# SEBELUM — tidak ada sinkronisasi (bug: kode lama dikompilasi)
cd "$REPO_DIR"
npm install >> $LOG_FILE 2>&1

# SESUDAH — kode baru dari SCP disinkronisasi lebih dulu
rsync -a --delete \
  --exclude 'node_modules' \
  --exclude 'dist' \
  --exclude '.git' \
  "$NEW_DIR/" "$REPO_DIR/"
```

#### E. Ringkasan Deployment di Akhir Log
```bash
# SESUDAH — ringkasan waktu tiap fase ditampilkan di akhir log
echo "  Total waktu  : ${TOTAL_DURATION} detik"
echo "    Fase 1 Sinkronisasi : ${FASE1_DURATION}s"
echo "    Fase 2 Backup       : ${FASE2_DURATION}s"
echo "    Fase 3 Build        : ${FASE3_DURATION}s"
echo "    Fase 4 Swap Berkas  : ${FASE4_DURATION}s"
echo "    Fase 5 Reload Nginx : ${FASE5_DURATION}s"
echo "    Fase 6 Health Check : ${FASE6_DURATION}s"
```

---

## 3. `scripts/healthcheck.sh`

### Sebelum:
```bash
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$APP_URL")
if [ "$HTTP_CODE" -eq 200 ]; then
  echo "[HEALTH CHECK] Berhasil! HTTP $HTTP_CODE diterima"
  exit 0
fi
```

### Sesudah:
```bash
# BARU: ukur response time sekaligus
RESPONSE=$(curl -s -o /dev/null \
  -w "%{http_code} %{time_total}" \
  --max-time 5 "$APP_URL")

HTTP_CODE=$(echo "$RESPONSE" | awk '{print $1}')
TIME_TOTAL=$(echo "$RESPONSE" | awk '{print $2}')
TIME_MS=$(echo "$TIME_TOTAL * 1000" | bc | cut -d'.' -f1)

if [ "$HTTP_CODE" -eq 200 ]; then
  echo "[HEALTH CHECK] OK — HTTP $HTTP_CODE diterima"
  echo "[HEALTH CHECK] Response time: ${TIME_MS} ms"  # BARU
  exit 0
fi
echo "[HEALTH CHECK] Percobaan $i/$MAX_RETRY — HTTP $HTTP_CODE (${TIME_MS} ms), retry ..."  # BARU
```

### Alasan Perubahan:
| No | Perubahan | Alasan |
|----|-----------|--------|
| 1 | Tambah `%{time_total}` di curl | Mengukur response time HTTP aplikasi |
| 2 | Konversi ke millisecond (ms) | Satuan yang lebih relevan untuk laporan pengujian |
| 3 | Tampilkan response time di log | Data ini digunakan pada sub-bab 4.2.3 dan 4.2.4 |

---

## Struktur File Log di Server EC2 (Setelah Perubahan)

```
/home/ubuntu/
└── logs/
    ├── deploy.log         ← Log detail per-fase setiap deployment
    └── deploy_record.log  ← Rekaman ringkasan waktu (1 baris per deployment)
```

### Contoh Isi `deploy.log`:
```
============================================================
[2026-08-02 19:00:01] DEPLOYMENT DIMULAI
  Branch  : main
  Commit  : a3f9b2c1
  Pesan   : Update tampilan halaman utama StressMeter
============================================================
[19:00:01] [FASE 1] Menyinkronkan kode dari /home/ubuntu/app_new ke /home/ubuntu/app ...
[19:00:03] [FASE 1] Sinkronisasi selesai. (2s)
[19:00:03] [FASE 2] Membuat backup versi aktif ke /home/ubuntu/backup/app_20260802_190001 ...
[19:00:04] [FASE 2] Backup selesai. (1s)
[19:00:04] [FASE 3] Menjalankan npm install --prefix src ...
[19:00:59] [FASE 3] Build selesai. Output: /home/ubuntu/app/src/dist (55s)
[19:00:59] [FASE 4] Menyalin dist/ ke /var/www/stressmeter ...
[19:01:02] [FASE 4] File berhasil disalin dan permission diatur. (3s)
[19:01:02] [FASE 5] Memvalidasi konfigurasi dan mereload Nginx ...
[19:01:03] [FASE 5] Nginx berhasil direload. (1s)
[19:01:03] [FASE 6] Menjalankan health check ...
[HEALTH CHECK] OK — Nginx aktif
[HEALTH CHECK] OK — HTTP 200 diterima dari http://localhost
[HEALTH CHECK] Response time: 12 ms
[19:01:12] [FASE 6] Health check berhasil. (9s)
============================================================
[2026-08-02 19:01:12] DEPLOYMENT BERHASIL
  Total waktu  : 71 detik
  Rincian      :
    Fase 1 Sinkronisasi : 2s
    Fase 2 Backup       : 1s
    Fase 3 Build        : 55s
    Fase 4 Swap Berkas  : 3s
    Fase 5 Reload Nginx : 1s
    Fase 6 Health Check : 9s
============================================================
```

### Contoh Isi `deploy_record.log`:
```
2026-08-02 19:01:12 | STATUS=SUKSES | BRANCH=main | COMMIT=a3f9b2c1 | TOTAL=71s | F1=2s | F2=1s | F3=55s | F4=3s | F5=1s | F6=9s
2026-08-02 20:15:44 | STATUS=SUKSES | BRANCH=main | COMMIT=d7e4c3a2 | TOTAL=68s | F1=1s | F2=1s | F3=52s | F4=3s | F5=1s | F6=10s
2026-08-02 21:30:05 | STATUS=GAGAL  | BRANCH=main | COMMIT=f1b5d9e0 | TOTAL=83s | F1=2s | F2=1s | F3=58s | F4=4s | F5=1s | F6=17s
```
