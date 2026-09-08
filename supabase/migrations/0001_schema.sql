-- Core schema for the kiosk attendance system.
-- Run in order: 0001_schema.sql, 0002_rls.sql, 0003_functions.sql, 0004_storage.sql

create extension if not exists vector;
create extension if not exists pgcrypto; -- gen_random_uuid()

-- One row per Supabase Auth user, distinguishing admins (login to the web
-- panel) from kiosk devices (sign in once, headless, from the Flutter app).
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  role text not null check (role in ('admin', 'kiosk')),
  full_name text,
  created_at timestamptz not null default now()
);

create table public.employees (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  email text,
  phone text,
  department text,
  employee_code text unique,
  is_active boolean not null default true,
  -- Driven by the kiosk's enrollment sync, not the admin panel:
  -- pending -> processing -> completed | failed
  embedding_status text not null default 'pending'
    check (embedding_status in ('pending', 'processing', 'completed', 'failed')),
  created_at timestamptz not null default now(),
  created_by uuid references auth.users (id)
);

create index employees_embedding_status_pending_idx
  on public.employees (embedding_status)
  where embedding_status = 'pending';

-- Raw enrollment photos captured in the admin panel (webcam). The kiosk
-- downloads these and turns them into embeddings itself -- see the schema
-- note in 0003_functions.sql for why embeddings are never computed here.
create table public.employee_photos (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.employees (id) on delete cascade,
  storage_path text not null,
  created_at timestamptz not null default now()
);

create index employee_photos_employee_id_idx on public.employee_photos (employee_id);

-- One row per (employee, enrollment photo), written only by the kiosk's
-- enrollment sync service via record_face_embedding().
create table public.face_embeddings (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.employees (id) on delete cascade,
  embedding vector(192) not null,
  source_photo_id uuid references public.employee_photos (id) on delete set null,
  created_at timestamptz not null default now()
);

create index face_embeddings_employee_id_idx on public.face_embeddings (employee_id);

-- Matching itself happens client-side on the kiosk (embeddings are pulled
-- into memory and compared with cosine similarity there), so no vector
-- index is needed here for that path -- this table is just the source of
-- truth the kiosk syncs from.

create table public.attendance_logs (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.employees (id),
  event_type text not null check (event_type in ('check_in', 'check_out')),
  event_date date not null,
  scanned_at timestamptz not null default now(),
  confidence real,
  kiosk_id uuid references public.profiles (id),
  unique (employee_id, event_date, event_type)
);

create index attendance_logs_employee_date_idx on public.attendance_logs (employee_id, event_date);
