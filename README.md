# Deploy Otomatis AWS EC2

Repositori ini berisi skrip otomasi untuk menjalankan perintah pada instance AWS EC2.

## Struktur Proyek
- `main.py`: Skrip utama untuk menjalankan perintah pada EC2.
- `ssh_config`: Konfigurasi SSH (gunakan file ini sebagai referensi untuk konfigurasi).

## Prasyarat
- Python 3.6+
- Library `boto3` (`pip install boto3`)
- Akses SSH ke instance EC2
- Key pair yang sesuai

## Konfigurasi
Pastikan file `ssh_config` atau informasi koneksi Anda sudah benar.

## Cara Menjalankan
```bash
python main.py
```