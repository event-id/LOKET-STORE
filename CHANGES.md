# DAFTAR PERUBAHAN — Integrasi Supabase LOKET STORE

Tanggal: 26 Oktober 2026
File yang diubah: **3** — `index.html`, `admin.html`, dan file baru `supabase-migration.sql`.
File lain di repository tidak disentuh. Nama `index.html` dan `admin.html` tidak berubah.

---

## 1. Temuan Audit (sebelum perubahan)

### Skema database terverifikasi (diperiksa langsung via REST API anon key)
| Tabel | Kolom terverifikasi |
|---|---|
| `events` | `id` (**UUID**), `title`, `slug`, `description`, `venue`, `event_date`, `price`, `image_url`, `status`, `created_at`, `updated_at` — **tidak ada** organizer/category/region/featured/laris/quota |
| `banners` | `id`, `title`, `image_url`, `link_url`, `position`, `active`, `created_at` |
| `tickets` | `id`, `event_id` (FK → events ✓), `ticket_code`, `customer_name`, `customer_email`, `status`, `issued_at` |
| `admin_users` | `user_id` (+`created_at`) |

- Fungsi `public.is_admin()` **sudah ada** (tanpa argumen, mengembalikan `false` untuk anon).
- RLS **terbukti aktif**: INSERT anonim ke `tickets` ditolak dengan kode `42501`.
- Relasi `tickets.event_id → events.id` terverifikasi (dipakai fitur join `events(title)` di admin).
- Semua tabel kosong saat audit (0 baris).

### Bug yang ditemukan
| # | Lokasi | Bug | Dampak |
|---|---|---|---|
| 1 | `admin.html` | `SUPABASE_ANON_KEY` patah 2 baris di dalam string literal | **SyntaxError — seluruh dashboard mati total** |
| 2 | `admin.html` | `SUPABASE_URL` diakhiri `/rest/v1/` (supabase-js menambah path ini sendiri) | Semua request mengarah ke `/rest/v1/rest/v1/...` → gagal |
| 3 | `admin.html` | `printTicket` membaca nama pembeli dari form yang sudah di-reset | Tiket tercetak tanpa nama pembeli |
| 4 | `admin.html` | Edit event memakai `toISOString().slice(0,16)` untuk `datetime-local` | Waktu bergeser (timezone) setiap kali event diedit |
| 5 | `index.html` | `parseRoute` memaksa `id:Number(parts[1])` | UUID dari Supabase menjadi `NaN` → **halaman detail event pasti rusak** |
| 6 | `index.html` | Tidak ada penanganan gagal-muat untuk data event/banner | Halaman kosong tanpa penjelasan bila backend bermasalah |

---

## 2. Perubahan `index.html` (desain & fungsi lama 100% dipertahankan)

**Prinsip:** komponen UI, routing hash, CSS, dan seluruh fungsi lama tidak diubah. Yang diganti hanya **sumber data** — melalui fungsi pemetaan terpisah sesuai instruksi.

1. **Sumber data dinamis**: array statis `EVENTS`/`BANNERS` diganti array kosong yang diisi dari Supabase (`public.events` dengan `status='published'`, `public.banners` dengan `active=true`) lewat `refreshCatalog()`. Konfigurasi koneksi ditambah di `CONFIG` (URL + publishable key — sama dengan admin.html).
2. **Fungsi pemetaan terpisah** `mapEventFromDB()` / `mapBannerFromDB()`: mengubah baris Supabase menjadi bentuk objek lama persis (`id, title, date, price, organizer, category, region, venue, img, featured, laris, desc`) sehingga semua komponen lama (kartu, carousel, detail, explore) bekerja tanpa modifikasi.
   - `event_date` (timestamptz) → tanggal lokal `YYYY-MM-DD`.
   - Kolom yang belum ada di DB diberi nilai bawaan yang jujur (`organizer: 'Panitia Event'`, `category: 'Lainnya'`, `region: 'LAINNYA'`, `img`: placeholder internal). Setelah migrasi SQL dijalankan, kolom asli otomatis terpakai.
3. **Detail event mendukung UUID dan slug** (`findEvent`) — memperbaiki bug #5 dan memenuhi syarat "detail mengambil data berdasarkan ID atau slug".
4. **State loading / siap / gagal**: skeleton asli untuk beranda saat memuat; halaman detail/explore menampilkan status "Memuat data…"; bila gagal → kartu "Gagal memuat data" + tombol **Coba Lagi** (tanpa data dummy yang menyamar sebagai data nyata).
5. **Empty state**: bila belum ada event terpublikasi, tampil pesan ramah; bagian beranda yang kosong (Rekomendasi/Laris/Terdekat) tidak dirender alih-alih menampilkan barisan kosong.
6. **Kategori & wilayah dinamis**: chip kategori dan kartu wilayah diturunkan dari data aktual (fallback ke daftar awal), tanpa mengubah komponen `catChip`/`regionCard`.
7. **Hardening kecil (tidak mengubah perilaku normal)**:
   - `fmtDate` dilindungi dari tanggal kosong/invalid (sebelumnya melempar exception).
   - URL gambar/tautan dari database difilter (`http(s)`, `data:image`, `/`, `#...`) — memblokir `javascript:` URL.
   - Placeholder gambar memakai teks "LOKET STORE" (sebelumnya "ARTATIX" — sisa branding lama).
   - Fallback logo: bila `logo.png` gagal dimuat, ikon disembunyikan dan teks brand tetap tampil.
8. **Alur pembelian lama dipertahankan 100%** (localStorage + `ORDER_API_URL` opsional) — diaudit, tidak diubah, karena pembayaran/kuota backend memang belum ada dan tidak boleh dianggap aman.

## 3. Perubahan `admin.html` (fitur sesuai spesifikasi, desain gelap tetap)

1. **Fix bug kritis #1 & #2** (key & URL) — dashboard kini benar-benar dapat terhubung.
2. **Statistik lengkap 7 kartu**: total event, event dipublikasikan, banner aktif, total e-tiket, valid, terpakai, dibatalkan. Total tiket memakai `count=exact` (akurat melebihi 100 baris terakhir).
3. **Form event lengkap**: tambah field Penyelenggara, Kategori (pilihan), Wilayah (datalist), Kuota, toggle Featured (Rekomendasi) dan Laris Manis — semuanya **opsional & tahan ketiadaan kolom**: bila kolom belum ada di DB, simpanan otomatis jatuh ke kolom inti dan muncul catatan untuk menjalankan migrasi (deteksi `PGRST204`/`42703`).
4. **Anti slug duplikat**: dicek ke database sebelum menyimpan (+ constraint unik di SQL sebagai tameng terakhir).
5. **Validasi tambahan**: URL gambar wajib `http(s)://`; waktu edit event kini dikonversi ke zona lokal (fix bug #4).
6. **Manajemen banner**: tambah **Edit** (sebelumnya hanya aktif/nonaktif & hapus), form bersih via tombol, pratinjau gambar juga saat edit, field link menerima rute internal `#/...` (dipakai website publik) selain `https://`.
7. **E-ticket**: kode acak kriptografis (crypto.getRandomValues, ~60 bit entropi) + retry otomatis bila bentrok (constraint unik); **pencarian tiket** (kode/nama/email/event); **transisi status tervalidasi** (valid→used/cancelled, used/cancelled→valid) di JS **dan** trigger database; tombol **Cetak** per baris.
8. **Cetak tiket dengan QR**: jendela cetak kini memuat event, nama, email, kode, dan QR berisi kode tiket (lib qrcodejs via CDN). QR hanya pembawa kode — validasi tetap lewat pencocokan kode ke database (dinyatakan jujur di lembar cetak).
9. **Anti dobel-kirim**: semua tombol submit/aksi di-disable selama permintaan berjalan; `loadAll` dilindungi try/catch dengan pesan error ramah.
10. **Keamanan**: tetap hanya publishable key; cek keanggotaan admin via `admin_users` tiap login & sesi; logout + penanganan sesi berakhir; tidak ada registrasi admin mandiri.

## 4. File baru: `supabase-migration.sql` (idempoten, aman diulang)

1. `is_admin()` dibuat/diperbarui (SECURITY DEFINER, bebas rekursi RLS).
2. Kolom events baru: `organizer, category, region, featured, laris, quota` (+ check kuota > 0).
3. Constraint unik `events.slug` & `tickets.ticket_code` (dengan pemeriksaan duplikat dulu — tidak pernah mengubah data) + 5 index performa.
4. **RLS deterministik**:
   - Publik (anon): hanya SELECT `events` berstatus `published` dan `banners` aktif.
   - Admin (authenticated + `is_admin()`): kendali penuh events/banners/tickets.
   - `tickets`: **nol akses publik** (data pelanggan terlindungi).
   - `admin_users`: hanya bisa baca baris sendiri; tidak ada INSERT/UPDATE/DELETE bagi non-service-role → tidak ada jalur promosi admin mandiri.
5. Trigger `tickets_status_transition`: validasi transisi status di level database.
6. Panduan verifikasi + cara mendaftarkan admin pertama (bagian [6] di file).


---

## 5. Penyempurnaan dashboard admin (5 November 2026)

File yang diubah: **admin.html**. File publik `index.html` dan skema database tidak diubah.

1. Menambahkan tombol **Muat ulang data** agar admin dapat mengambil data terbaru tanpa memuat ulang seluruh halaman.
2. Menambahkan pencarian event berdasarkan nama, lokasi, slug, atau penyelenggara serta filter status (semua/published/draft/cancelled).
3. Menyelaraskan validasi kuota di form dengan constraint database: kuota harus bilangan bulat minimal 1 atau dikosongkan (tanpa batas kuota).
4. Menambahkan validasi harga agar hanya menerima bilangan bulat non-negatif dan validasi urutan banner agar bilangan bulat non-negatif.
5. Memperbaiki representasi statistik tiket ketika permintaan `count=exact` gagal: dashboard menampilkan `—` alih-alih angka fallback dari maksimum 100 tiket terbaru yang berpotensi menyesatkan.
6. Memperkuat pembentukan skrip QR pada halaman cetak dengan encoding JSON dan escaping karakter `<` agar kode tiket tidak dapat memutus elemen `<script>` pada jendela cetak.
7. Menjelaskan bahwa daftar e-ticket hanya menampilkan maksimal 100 tiket terbaru, sedangkan statistik menghitung keseluruhan data.

### Pemeriksaan pada paket revisi
- JavaScript module `admin.html`: lolos pemeriksaan sintaks Node.js (`node --check`).
- Pemeriksaan login admin, operasi tulis, dan perubahan data live tidak dijalankan karena memerlukan kredensial admin dan persetujuan untuk menulis ke database Supabase produksi.
- Tidak ada perubahan pada `index.html`, `supabase-migration.sql`, atau data database.

## Upload gambar langsung dari dashboard admin

- Menambahkan upload gambar lokal untuk gambar event dan banner melalui Supabase Storage bucket `a1-assets`.
- URL publik otomatis dimasukkan ke kolom `image_url` pada formulir setelah upload berhasil.
- Menambahkan pratinjau gambar, status upload, validasi MIME type, dan batas ukuran 5 MB.
- Menambahkan kebijakan Storage: pembacaan publik untuk gambar website, sedangkan insert/update/delete hanya untuk admin yang lolos `public.is_admin()`.
- Menambahkan petunjuk setup Storage di `DEPLOY.md`; jalankan ulang `supabase-migration.sql` terbaru.
