-- ============================================================================
-- LOKET STORE — supabase-migration.sql
-- ============================================================================
-- CARA PAKAI:
--   1. Buka Supabase Dashboard > SQL Editor, klik New query.
--   2. Salin SELURUH isi file ini, klik Run. Aman dijalankan berulang (idempoten).
--
-- YANG DILAKUKAN FILE INI:
--   [1] Memastikan fungsi public.is_admin() tersedia (dipakai kebijakan RLS).
--   [2] Menambah kolom events yang dibutuhkan website publik:
--       organizer, category, region, featured, laris, quota.
--   [3] Keunikan slug event dan kode tiket (anti-duplikat) + index performa.
--   [4] Row Level Security (RLS) yang deterministik:
--         - Publik (anon): hanya BACA event berstatus 'published' dan banner aktif.
--         - Admin (tabel admin_users): kelola event/banner/tiket penuh.
--         - Publik TIDAK bisa baca tiket pelanggan (data pelanggan terlindungi).
--         - Tidak ada jalur pendaftaran admin mandiri (INSERT admin_users hanya
--           lewat SQL Editor / service_role).
--   [5] Trigger validasi transisi status tiket di sisi DATABASE (bukan hanya JS):
--         valid -> used | cancelled ; used -> valid ; cancelled -> valid.
--
-- DAMPAK: tidak ada data yang dihapus/diubah. Jika ada slug/kode tiket duplikat,
-- constraint unik TIDAK akan dibuat dan pesan NOTICE muncul (lihat bagian 3).
--
-- CEK KEBIJAKAN LAMA (opsional, jalankan dulu bila ingin audit):
--   select schemaname, tablename, policyname, cmd, roles, qual
--   from pg_policies where schemaname = 'public'
--   order by tablename, policyname;
-- Jika terdapat kebijakan lama yang lebih longgar (mis. "all to anon"), hapus
-- kebijakan tersebut agar pembatasan di file ini efektif. Kebijakan yang dibuat
-- file ini bernama: events_public_read, events_admin_all, banners_public_read,
-- banners_admin_all, tickets_admin_all, admin_users_read_own.
-- ============================================================================


-- ============================================================================
-- [1] FUNGSI is_admin()
-- Dipakai semua kebijakan RLS di bawah. SECURITY DEFINER agar tidak terjadi
-- rekursi RLS ketika membaca admin_users. Idempoten (create or replace).
-- ============================================================================
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.admin_users
    where user_id = auth.uid()
  );
$$;


-- ============================================================================
-- [2] KOLOM TAMBAHAN events (idempoten — add column if not exists)
-- Kolom ini dipakai halaman publik (kategori, wilayah, penyelenggara,
-- Rekomendasi/Laris Manis). Default aman sehingga data lama tetap valid.
-- ============================================================================
alter table public.events
  add column if not exists organizer text not null default '',
  add column if not exists category  text not null default 'Lainnya',
  add column if not exists region    text not null default '',
  add column if not exists featured  boolean not null default false,
  add column if not exists laris     boolean not null default false,
  add column if not exists quota     integer;

-- Kuota (bila diisi) harus bernilai masuk akal:
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'events_quota_positive' and conrelid = 'public.events'::regclass
  ) then
    alter table public.events
      add constraint events_quota_positive check (quota is null or quota > 0);
  end if;
end $$;


-- ============================================================================
-- [3] KEUNIKAN SLUG & KODE TIKET + INDEX PERFORMA (idempoten)
-- ============================================================================
-- Slug event harus unik. Bila masih ada duplikat, constraint tidak dibuat dan
-- muncul NOTICE — rapikan dulu data duplikatnya lalu jalankan ulang file ini.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'events_slug_key' and conrelid = 'public.events'::regclass
  ) then
    if exists (select 1 from public.events where slug is not null group by slug having count(*) > 1) then
      raise notice 'LEWATI: masih ada slug duplikat di tabel events. Bersihkan duplikat, lalu jalankan ulang migrasi.';
    else
      alter table public.events add constraint events_slug_key unique (slug);
    end if;
  end if;
end $$;

-- Kode tiket harus unik (mencegah duplikasi kode tiket di tingkat database).
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'tickets_ticket_code_key' and conrelid = 'public.tickets'::regclass
  ) then
    if exists (select 1 from public.tickets group by ticket_code having count(*) > 1) then
      raise notice 'LEWATI: masih ada kode tiket duplikat. Bersihkan duplikat, lalu jalankan ulang migrasi.';
    else
      alter table public.tickets add constraint tickets_ticket_code_key unique (ticket_code);
    end if;
  end if;
end $$;

create index if not exists events_status_idx          on public.events (status);
create index if not exists events_event_date_idx      on public.events (event_date);
create index if not exists banners_active_position_idx on public.banners (active, position);
create index if not exists tickets_event_id_idx       on public.tickets (event_id);
create index if not exists tickets_issued_at_idx      on public.tickets (issued_at);


-- ============================================================================
-- [4] ROW LEVEL SECURITY
-- Status terverifikasi saat audit: RLS SUDAH AKTIF dan INSERT anonim DITOLAK.
-- Kebijakan di bawah dibuat eksplisit agar kondisi keamanan deterministik.
-- drop policy if exists + create policy = aman dijalankan berulang.
-- ============================================================================
alter table public.events      enable row level security;
alter table public.banners     enable row level security;
alter table public.tickets     enable row level security;
alter table public.admin_users enable row level security;

-- ---- events: publik baca yang published saja; admin kelola penuh ----
drop policy if exists "events_public_read" on public.events;
create policy "events_public_read"
  on public.events
  for select
  to anon, authenticated
  using (status = 'published');

drop policy if exists "events_admin_all" on public.events;
create policy "events_admin_all"
  on public.events
  for all
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- ---- banners: publik baca yang aktif saja; admin kelola penuh ----
drop policy if exists "banners_public_read" on public.banners;
create policy "banners_public_read"
  on public.banners
  for select
  to anon, authenticated
  using (active = true);

drop policy if exists "banners_admin_all" on public.banners;
create policy "banners_admin_all"
  on public.banners
  for all
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- ---- tickets: TIDAK ADA akses publik sama sekali; hanya admin ----
drop policy if exists "tickets_admin_all" on public.tickets;
create policy "tickets_admin_all"
  on public.tickets
  for all
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- ---- admin_users: admin hanya bisa melihat barisnya sendiri ----
-- Tidak ada policy INSERT/UPDATE/DELETE -> pendaftaran admin HANYA via SQL
-- Editor (service_role), sehingga pengguna biasa tidak bisa mempromosikan
-- dirinya sendiri menjadi admin.
drop policy if exists "admin_users_read_own" on public.admin_users;
create policy "admin_users_read_own"
  on public.admin_users
  for select
  to authenticated
  using (user_id = auth.uid() or public.is_admin());


-- ============================================================================
-- [5] VALIDASI TRANSISI STATUS TIKET DI SISI DATABASE
-- Transisi yang diizinkan:
--   INSERT      : status awal harus valid / used / cancelled
--   valid     -> used | cancelled   (tiket dipakai atau dibatalkan)
--   used      -> valid              (koreksi salah scan)
--   cancelled -> valid              (aktifkan kembali)
-- Mencegah manipulasi status langsung dari browser (tidak bergantung pada JS).
-- ============================================================================
create or replace function public.enforce_ticket_status_transition()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'INSERT' then
    if new.status not in ('valid','used','cancelled') then
      raise exception 'Status tiket tidak dikenal: %', new.status;
    end if;
    return new;
  end if;

  -- UPDATE
  if new.status = old.status then
    return new;
  end if;

  if not (
    (old.status = 'valid'     and new.status in ('used','cancelled')) or
    (old.status = 'used'      and new.status = 'valid') or
    (old.status = 'cancelled' and new.status = 'valid')
  ) then
    raise exception 'Perubahan status tiket dari "%" ke "%" tidak diizinkan', old.status, new.status;
  end if;

  return new;
end;
$$;

drop trigger if exists tickets_status_transition on public.tickets;
create trigger tickets_status_transition
  before insert or update of status
  on public.tickets
  for each row
  execute function public.enforce_ticket_status_transition();


-- ============================================================================
-- [6] VERIFIKASI SETELAH MIGRASI (jalankan manual di SQL Editor bila perlu)
-- ============================================================================
-- a) Kolom events:
--    select column_name, data_type, column_default
--    from information_schema.columns where table_schema='public' and table_name='events';
--
-- b) Daftar kebijakan RLS aktif:
--    select tablename, policyname, cmd, roles from pg_policies
--    where schemaname='public' order by tablename;
--
-- c) Mendaftarkan admin pertama (HANYA lewat SQL Editor):
--    1) Buat dulu user di Dashboard > Authentication > Users > Add user
--       (email + password, centang Auto Confirm User).
--    2) Lalu:
--    insert into public.admin_users (user_id)
--    select id from auth.users where email = 'email-admin-anda@contoh.com'
--    on conflict (user_id) do nothing;
--
-- d) Uji cepat RLS (harus 0 baris saat dijalankan sebagai anon):
--    set local role anon;
--    select count(*) from public.events where status <> 'published';
--    select count(*) from public.tickets;
--    reset role;
-- ============================================================================


-- ============================================================================
-- [7] SUPABASE STORAGE UNTUK UPLOAD GAMBAR DARI DASHBOARD ADMIN
-- Jalankan blok ini di Supabase SQL Editor setelah fungsi public.is_admin()
-- tersedia. Bucket publik hanya untuk membaca gambar; tulis/hapus dibatasi admin.
-- ============================================================================
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'a1-assets',
  'a1-assets',
  true,
  5242880,
  array['image/jpeg','image/png','image/webp','image/gif']::text[]
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "a1_assets_public_read" on storage.objects;
create policy "a1_assets_public_read"
  on storage.objects for select
  to anon, authenticated
  using (bucket_id = 'a1-assets');

drop policy if exists "a1_assets_admin_insert" on storage.objects;
create policy "a1_assets_admin_insert"
  on storage.objects for insert
  to authenticated
  with check (bucket_id = 'a1-assets' and public.is_admin());

drop policy if exists "a1_assets_admin_update" on storage.objects;
create policy "a1_assets_admin_update"
  on storage.objects for update
  to authenticated
  using (bucket_id = 'a1-assets' and public.is_admin())
  with check (bucket_id = 'a1-assets' and public.is_admin());

drop policy if exists "a1_assets_admin_delete" on storage.objects;
create policy "a1_assets_admin_delete"
  on storage.objects for delete
  to authenticated
  using (bucket_id = 'a1-assets' and public.is_admin());
