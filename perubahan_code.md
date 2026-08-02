# Laporan Perubahan Kode (Revisi Pipeline CI/CD)

Dokumen ini mencatat perubahan yang telah dilakukan pada repositori proyek `deploy-otomasi-ec2` untuk memperbaiki bug alur kerja yang tidak sinkron dan masalah kegagalan instalasi dependensi React pada pipeline CI/CD.

---

## 1. File `.github/workflows/deploy.yml`

### **Sebelum Perubahan:**
```yaml
      - name: Install dependencies dan build (tahap CI)
        run: |
          npm install
          npm run build --if-present
```

### **Setelah Perubahan:**
```yaml
      - name: Install dependencies dan build (tahap CI)
        run: |
          npm install --prefix src
          npm run build
```

### **Penjelasan Rationale:**
- **Masalah:** File `package.json` di root proyek hanya berisi delegasi perintah (`scripts`) dan tidak mendefinisikan dependensi React/Vite. Dependensi sebenarnya berada di dalam `src/package.json`. Menjalankan `npm install` langsung di root tidak akan menginstal dependensi React tersebut, sehingga proses `npm run build` pada runner CI akan gagal karena tidak menemukan modul seperti `vite`.
- **Solusi:** Menambahkan argumen `--prefix src` pada saat menjalankan `npm install` agar NPM menginstal pustaka-pustaka React ke dalam folder `src/node_modules` sebelum proses build dijalankan.

---

## 2. File `scripts/deploy.sh`

### **Sebelum Perubahan:**
```bash
# ─────────────────────────────────────────────────────────────────────────────
# FASE 2: BUILD — Install dependencies dan build React dengan Vite
# ─────────────────────────────────────────────────────────────────────────────
echo "[FASE 2] Menjalankan npm install dan npm run build..." >> $LOG_FILE
cd "$REPO_DIR"
npm install >> $LOG_FILE 2>&1
npm run build >> $LOG_FILE 2>&1
echo "[FASE 2] Build React selesai. Output: $BUILD_SRC" >> $LOG_FILE
```

### **Setelah Perubahan:**
```bash
# ─────────────────────────────────────────────────────────────────────────────
# FASE 2: BUILD — Sinkronisasi kode baru dan jalankan build React
# ─────────────────────────────────────────────────────────────────────────────
echo "[FASE 2] Menyinkronkan kode baru dari app_new..." >> $LOG_FILE
mkdir -p "$REPO_DIR"
rsync -a --delete --exclude 'node_modules' --exclude 'dist' /home/ubuntu/app_new/ "$REPO_DIR/"

echo "[FASE 2] Menjalankan npm install dan npm run build..." >> $LOG_FILE
cd "$REPO_DIR"
npm install --prefix src >> $LOG_FILE 2>&1
npm run build >> $LOG_FILE 2>&1
echo "[FASE 2] Build React selesai. Output: $BUILD_SRC" >> $LOG_FILE
```

### **Penjelasan Rationale:**
- **Masalah 1 (Inkonsistensi Folder):** Pada `deploy.yml`, berkas kode sumber dikirim oleh GitHub Actions via SCP ke direktori `/home/ubuntu/app_new`. Namun di `deploy.sh`, `REPO_DIR` merujuk ke `/home/ubuntu/app` dan build langsung dijalankan di sana tanpa adanya pemindahan berkas baru. Hal ini mengakibatkan server terus mengompilasi kode lama atau memicu error jika direktori kosong.
- **Masalah 2 (Redundansi/Penghapusan Node Modules):** Jika berkas langsung disalin begitu saja atau ditimpa, folder `node_modules` yang sangat besar terancam ikut terhapus atau harus diunduh ulang dari awal pada setiap deployment, yang memicu lambatnya proses deployment.
- **Solusi:**
  1. Menambahkan perintah `rsync -a --delete --exclude 'node_modules' --exclude 'dist' /home/ubuntu/app_new/ "$REPO_DIR/"`. Ini menyinkronkan file baru dari `app_new` ke `app` secara efisien dan aman.
  2. Mengecualikan (`--exclude`) folder `node_modules` dan `dist` agar rsync tidak menghapus library yang sudah terpasang di server EC2.
  3. Mengubah `npm install` menjadi `npm install --prefix src` agar dependensi di dalam folder `src` terinstal secara konsisten dengan struktur proyek.
