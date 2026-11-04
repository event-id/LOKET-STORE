# DEPLOY & KONFIGURASI — LOKET STORE + Supabase

## 1. Konfigurasi Supabase yang HARUS dilakukan manual (sekali)

### 1.1 Jalankan migrasi (WAJIB — tanpa ini dashboard & filter publik belum aktif penuh)
1. Buka **Supabase Dashboard → SQL Editor → New query**.
2. Salin seluruh isi `supabase-migration.sql`, klik **Run**.
3. Pastikan hasil "Success". Jika ada NOTICE soal slug/kode tiket duplikat,
   rapikan data duplikatnya lalu jalankan ulang file (idempoten).

Yang didapat: kolom event tambahan (penyelenggara, kategori, wilayah, featured,
laris, kuota), keunikan slug & kode tiket, kebijakan RLS deterministik, dan
trigger transisi status tiket.

### 1.2 Buat akun admin pertama
1. **Authentication → Users → Add user → Create new user**:
   isi email + password, aktifkan **Auto Confirm User**.
2. Kembali ke **SQL Editor**, jalankan (ganti email):
   ```sql
   insert into public.admin_users (user_id)
   select id from auth.users where email = 'email-admin-anda@contoh.com'
   on conflict (user_id) do nothing;
   ```
3. Admin tambahan: buat user Auth-nya lalu ulangi langkah 2.
   Tidak ada jalur pendaftaran admin dari halaman publik — memang disengaja.

### 1.3 Periksa setelan Auth (opsional tapi disarankan)
- **Authentication → Providers → Email**: aktif.
- **Authentication → URL Configuration**: isi Site URL dengan domain GitHub Pages
  Anda (mis. `https://username.github.io/repo`) agar email verifikasi/reset
  mengarah ke alamat yang benar.

### 1.4 (Opsional) Storage gambar
Saat ini gambar memakai **URL publik** (jadi kebijakan yang jujur: belum ada
fitur upload di dashboard). Bila nanti ingin upload langsung:
buat bucket publik di **Storage**, lalu unggah gambar lewat Dashboard dan
tempel URL-nya di form admin. Jangan klaim "upload" berfungsi sebelum ini
dilakukan — dashboard saat ini secara eksplisit meminta URL gambar.

## 2. Deploy ke GitHub Pages

1. Commit & push ketiga file ke repository yang sama (folder root):
   ```
   index.html  admin.html  supabase-migration.sql  (opsional: docs)
   ```
   Jangan ubah nama file. File lain yang sudah ada (mis. `logo.png`) dibiarkan.
2. **Settings → Pages** → Source: *Deploy from a branch* → Branch: `main`
   → Folder: `/ (root)` → Save.
3. Setelah build selesai (~1–2 menit), situs tersedia di:
   `https://<username>.github.io/<nama-repo>/`
4. Buka `.../<nama-repo>/` (beranda) dan `.../<nama-repo>/admin.html` (dashboard).
   Routing hash (`#/`, `#/explore`, `#/event/...`) aman untuk subpath.

## 3. Cara kerja keseharian

| Aksi di admin.html | Efek di index.html |
|---|---|
| Tambah/edit event, status **Published** | Tampil di publik (muat ulang halaman bila sudah terbuka) |
| Status **Draft** / **Cancelled** | Otomatis hilang dari publik (query publik hanya mengambil `published`) |
| Tambah banner aktif + urutan | Tampil di carousel beranda sesuai urutan |
| Nonaktifkan banner | Hilang dari carousel |
| Terbitkan e-tiket | Kode unik siap disalin/cetak (QR berisi kode tiket) |
| Tandai dipakai / batalkan / set valid | Terjaga oleh validasi transisi (JS + trigger database) |

## 4. Keamanan — ringkas

- Hanya **publishable/anon key** di kedua file (bukan service_role). Kunci ini
  memang publik; yang melindungi data adalah RLS.
- Publik: hanya baca event `published` + banner aktif. Tabel tiket & pelanggan
  **tidak bisa dibaca publik sama sekali**.
- Tulis data: hanya akun authenticated yang ada di `admin_users` (cek
  `is_admin()` di setiap kebijakan).
- Tidak ada password/rahasia di `localStorage`; sesi dikelola Supabase Auth.
- Pembayaran/kuota/penerbitan tiket otomatis **belum** dianggap aman: alur beli
  di halaman publik menyimpan pesanan lokal berstatus *Pending* (perilaku lama
  dipertahankan); transaksi nyata butuh backend atomik (Edge Function/RPC) dan
  belum diimplementasikan sesuai batasan tugas.

## 5. Troubleshooting

| Gejala | Penyebab & solusi |
|---|---|
| Beranda: "Gagal memuat data … row-level security" | Migrasi SQL belum dijalankan → jalankan 1.1 |
| Login admin: "Akun ini belum terdaftar sebagai admin" | Email ada di Auth tapi belum di `admin_users` → jalankan 1.2 langkah 2 |
| Event tidak tampil di publik | Status masih `Draft`, atau tabel kosong; cek status = Published |
| Banner tidak tampil | Checkbox aktif belum dicentang, atau URL gambar tidak valid |
| Gambar rusak | URL bukan `http(s)://` publik; placeholder internal otomatis dipakai |
| Ganti kunci Supabase | Edit `CONFIG` di `index.html` dan konstanta di `admin.html` — keduanya harus sama |

## Upload gambar langsung dari dashboard admin

Dashboard admin mendukung upload gambar event dan banner ke Supabase Storage.

1. Buka Supabase Dashboard → SQL Editor.
2. Jalankan ulang seluruh file `supabase-migration.sql` versi terbaru. Migrasi ini idempoten dan kini juga membuat bucket publik `a1-assets` dengan batas 5 MB serta tipe JPG/PNG/WEBP/GIF.
3. Pastikan akun yang login terdaftar di `public.admin_users` dan `public.is_admin()` mengembalikan `true` untuk akun tersebut.
4. Buka `admin.html`, login sebagai admin, pilih Event atau Banner.
5. Pilih file gambar lalu tekan tombol **Upload gambar event** atau **Upload gambar banner**. URL publik akan terisi otomatis pada kolom URL; lanjutkan dengan menyimpan formulir.

File gambar dapat dibaca publik melalui URL karena dipakai pada website. Hanya pengguna terautentikasi yang lolos `public.is_admin()` yang dapat mengunggah, mengubah, atau menghapus objek di bucket. Jangan pernah menaruh `service_role` key di HTML.

Batas upload dari antarmuka: 5 MB per file. Format yang diterima: JPEG, PNG, WEBP, dan GIF.
