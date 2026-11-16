# Liburan Seru — Jastip & Travel

APK Android (Flutter) untuk jastip dan travel seluruh dunia. Offline-first.

## Fitur v1.0.0+1
- **Jastip**: tambah penitip, nama barang, mata uang (15 mata uang), harga asing,
  estimasi IDR otomatis, status Belum Bayar / DP / Lunas (ketuk chip untuk ganti),
  total nilai + total belum lunas, filter status. Data tersimpan offline di HP
  (SharedPreferences, key `ls_jastip_items`).
- **Travel**: 17 destinasi seluruh dunia (Tokyo, Kyoto, Osaka, Seoul, Singapura,
  Bangkok, Bali, Kuala Lumpur, London, Paris, Roma, Madrid, Swiss Alps, Dubai,
  Istanbul, New York, Sydney) — cari + filter wilayah, detail city pass,
  highlight, itinerary 3–4 hari. Tombol "Buat Jastip dari kota ini" menyetel
  mata uang Jastip ke mata uang kota itu.
- **Kurs**: 15 kurs default ke IDR (perkiraan Nov 2026), bisa diubah manual,
  tombol Perbarui Kurs Online (open.er-api.com, fallback ke kurs manual bila gagal),
  Reset ke default. Tersimpan offline (`ls_rates`).

## Build
```bash
source ~/.bashrc
export GRADLE_USER_HOME=~/workspace/gradle-home
flutter build apk --release
```
APK: `build/app/outputs/flutter-apk/app-release.apk`

## Catatan
- Tidak pakai Supabase / server — sengaja offline-first, supaya tidak kena
  blokir jaringan seperti tab Sekolah di Nihongo Santai.
- Harga pass & kurs hanya perkiraan, cek ulang sebelum berangkat / transaksi.
