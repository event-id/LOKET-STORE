# HASIL PENGUJIAN AKTUAL — Integrasi Supabase LOKET STORE

Semua pengujian di bawah benar-benar dijalankan (bukan asumsi). Lingkungan uji:
browser headless (Chromium via agent-browser) + server lokal + koneksi langsung
ke project Supabase produksi milik Anda (`pzkznojarbsqnioxifqj`) menggunakan
publishable key yang sama dengan yang ada di file. **Tidak ada data uji yang
ditulis ke database produksi** — probe tulis sengaja memakai id yang tidak ada
atau FK yang rusak sehingga nol dampak.

## A. Pengujian database (via REST, anon key)

| # | Uji | Hasil |
|---|-----|-------|
| 1 | Koneksi REST dengan publishable key | ✅ HTTP 200 |
| 2 | SELECT `events` (anon) | ✅ 200, 0 baris (tabel kosong) |
| 3 | SELECT `banners` (anon) | ✅ 200, 0 baris |
| 4 | INSERT `tickets` anonim (probe FK rusak — aman) | ✅ **DITOLAK RLS** `42501` — kebijakan tulis publik sudah tertutup |
| 5 | Fungsi `is_admin()` RPC (anon) | ✅ ada, mengembalikan `false` |
| 6 | Relasi `tickets→events` (embedded select) | ✅ valid |
| 7 | Skema kolom (probe per kolom) | ✅ sesuai daftar di CHANGES.md — tidak ada kolom yang diasumsikan |

## B. Pengujian website publik (`index.html`, server lokal + browser headless)

| # | Uji | Hasil |
|---|-----|-------|
| 1 | Muat beranda, cek console & page error | ✅ 0 error |
| 2 | DB kosong → tampil empty state "Belum ada event yang dipublikasikan" (bukan data dummy) | ✅ |
| 3 | Mapper `mapEventFromDB` dengan 3 baris berbentuk persis Supabase (UUID, timestamptz, null) | ✅ date/region/organizer/img placeholder/kuota benar |
| 4 | Mapper `mapBannerFromDB` + fallback tag/sub | ✅ |
| 5 | Render beranda dengan data simulasi: 5 bagian asli, kartu, carousel, dots | ✅ persis layout lama |
| 6 | Detail event via **UUID** `#/event/<uuid>` | ✅ judul, badge, harga, EO tampil |
| 7 | Detail event via **slug** `#/event/jazz-malam` | ✅ |
| 8 | Jelajah: chip kategori (2 event "Musik" ditemukan) | ✅ |
| 9 | Jelajah: pencarian teks "bandung" → 1 hasil sesuai | ✅ |
| 10 | Alur pembelian lama: validasi form → submit → order tersimpan → toast → halaman "Tiket Saya" menampilkan tiket | ✅ 100% berfungsi |
| 11 | Koneksi diputus (offline) → pulihkan → data termuat ulang | ✅ recovery normal |
| 12 | UI state error: kartu "Gagal memuat data" + tombol "Coba Lagi", tanpa kartu palsu | ✅ (diverifikasi langsung pada state error) |
| 13 | Mobile 360px: tidak ada scroll horizontal halaman | ✅ (sebagai pembanding, file ASLI justru overflow 406px di 360px) |
| 14 | Screenshot: beranda desktop, admin login, beranda mobile | ✅ tersimpan |

Catatan jujur: karena tabel produksi Anda masih kosong, uji #5 memakai injeksi
data berbentuk DB di browser (lokal, tidak menyentuh produksi) agar alur render
dapat diverifikasi penuh. Setelah Anda menambah event via admin, alur yang sama
yang teruji itulah yang berjalan dengan data nyata.

## C. Pengujian dashboard admin (`admin.html`)

| # | Uji | Hasil |
|---|-----|-------|
| 1 | Muat halaman, cek console & page error | ✅ 0 error (sebelum perbaikan: SyntaxError total) |
| 2 | Login dilihat, dashboard tersembunyi sebelum login | ✅ |
| 3 | Login kredensial salah → pesan "Invalid login credentials" dari Supabase Auth | ✅ **membuktikan URL & key hasil perbaikan benar-benar terhubung** |
| 4 | Tab Event/Banner/E-ticket berpindah | ✅ |
| 5 | Slug otomatis dari judul ("Konser Jazz Malam Spesial!" → `konser-jazz-malam-spesial`) | ✅ |
| 6 | Validasi URL gambar `javascript:alert(1)` ditolak | ✅ |
| 7 | Validasi link banner: `javascript:` ditolak; `#/event/abc` lolos validasi | ✅ |
| 8 | **INSERT banner tanpa login langsung ke API** | ✅ **DITOLAK RLS**: "new row violates row-level security policy for table \"banners\"" — bukti tulis tanpa admin mustahil |
| 9 | 7 kartu statistik + field form baru (organizer/category/region/quota/featured/laris) | ✅ tampil semua |

## D. Yang BELUM dapat diuji (jujur, beserta alasannya)

1. **Login admin sah sampai ke dashboard** — kredensial admin tidak (dan tidak
   boleh) saya miliki. Mekanismenya (signInWithPassword → cek `admin_users` →
   muat data) sudah teruji per-bagian: #C3 membuktikan auth jalan, #A5
   membuktikan `is_admin()` jalan, dan kebijakan RLS admin dibuat oleh
   `supabase-migration.sql`. Segera setelah admin pertama didaftarkan (lihat
   DEPLOY.md langkah 4), alur penuh ini aktif.
2. **Tambah/edit/hapus event & banner secara nyata dari dashboard** — membutuhkan
   login admin (poin 1) dan akan menulis ke produksi. Pengecekan per-komponen
   sudah dilakukan (#C5–C9), dan jalur penulisan terbukti terbuka HANYA bagi
   admin oleh RLS (#C8 membuktikan jalur non-admin tertutup).
3. **Terbitkan & ubah status e-tiket nyata** — alasan sama dengan poin 2;
   transisi status juga dijaga trigger database hasil migrasi.
4. **Kirim email / pembayaran / pemindaian tiket** — memang belum ada layanannya;
   tidak diklaim berfungsi. Cetak e-tiket (dengan QR berisi kode) sudah tersedia.
5. **GitHub Pages subpath** — tidak ada repository URL yang diberikan; namun
   semua aset relatif (`logo.png`), routing hash, dan CDN absolut aman untuk
   subpath (mis. `username.github.io/repo/`). Panduan deploy disertakan.

## E. Langkah verifikasi cepat setelah Anda deploy (10 menit)

1. Jalankan `supabase-migration.sql` (SQL Editor) → cek NOTICE/kesalahan.
2. Daftarkan admin pertama (bagian [6c] file SQL).
3. Buka `admin.html` → login → tambah 1 event (status **Published**) + 1 banner aktif.
4. Buka `index.html` → event & banner harus tampil; klik detail; cek `#/explore`.
5. Ubah status event menjadi Draft di admin → muat ulang `index.html` → event harus hilang dari publik.
