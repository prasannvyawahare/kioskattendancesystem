-- Row Level Security for the kiosk attendance system.
--
-- current_user_role() is SECURITY DEFINER so it can read `profiles` without
-- itself being blocked by profiles' own RLS (the standard Supabase pattern
-- for avoiding recursive-policy deadlock on a role-lookup table).
create or replace function public.current_user_role()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select role from public.profiles where id = auth.uid();
$$;

grant execute on function public.current_user_role() to authenticated;

alter table public.profiles enable row level security;
alter table public.employees enable row level security;
alter table public.employee_photos enable row level security;
alter table public.face_embeddings enable row level security;
alter table public.attendance_logs enable row level security;

-- profiles: everyone can read their own row; admins can read/manage all.
create policy "profiles_select_own"
  on public.profiles for select
  using (id = auth.uid());

create policy "profiles_admin_all"
  on public.profiles for all
  using (public.current_user_role() = 'admin')
  with check (public.current_user_role() = 'admin');

-- employees: admins have full CRUD; kiosk devices may only read active rows.
create policy "employees_admin_all"
  on public.employees for all
  using (public.current_user_role() = 'admin')
  with check (public.current_user_role() = 'admin');

create policy "employees_kiosk_select_active"
  on public.employees for select
  using (public.current_user_role() = 'kiosk' and is_active = true);

-- employee_photos: admins have full CRUD; kiosk devices only read (to
-- download photos for the enrollment sync).
create policy "employee_photos_admin_all"
  on public.employee_photos for all
  using (public.current_user_role() = 'admin')
  with check (public.current_user_role() = 'admin');

create policy "employee_photos_kiosk_select"
  on public.employee_photos for select
  using (public.current_user_role() = 'kiosk');

-- face_embeddings: no direct INSERT policy for anyone -- all writes go
-- through record_face_embedding() (0003_functions.sql). Admins can read/
-- delete (e.g. to force re-enrollment); kiosk devices only read (to build
-- their in-memory matcher).
create policy "face_embeddings_admin_select"
  on public.face_embeddings for select
  using (public.current_user_role() = 'admin');

create policy "face_embeddings_admin_delete"
  on public.face_embeddings for delete
  using (public.current_user_role() = 'admin');

create policy "face_embeddings_kiosk_select"
  on public.face_embeddings for select
  using (public.current_user_role() = 'kiosk');

-- attendance_logs: no direct INSERT policy for anyone -- all writes go
-- through mark_attendance() (0003_functions.sql), which is the only place
-- the check-in/check-out decision is made. Admins can read everything.
create policy "attendance_logs_admin_select"
  on public.attendance_logs for select
  using (public.current_user_role() = 'admin');
