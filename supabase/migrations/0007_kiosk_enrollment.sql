-- On-device enrollment support: a single admin-managed settings row (org
-- name, greeting templates, voice/enrollment toggles, PIN hash) plus the
-- RPCs the kiosk uses to PIN-gate and perform enrollment itself instead of
-- only through the admin panel. See kiosk_app/lib/screens/add_member_screen.dart
-- and pin_entry_screen.dart for the client side of this.

-- Singleton settings row -- the standard Postgres "only one row allowed"
-- trick: a boolean primary key that can only ever be `true`.
create table public.kiosk_settings (
  id boolean primary key default true check (id),
  institution_name text not null default 'Your Organization',
  -- Cosmetic only -- drives kiosk-side copy like the "Add {member_label}"
  -- button. The admin panel's existing "Employees" nav/copy is left as-is.
  member_label text not null default 'Member',
  voice_enabled boolean not null default true,
  -- Server-side kill switch, ANDed with the kiosk's own
  -- --dart-define=ENABLE_ENROLLMENT build flag -- lets an admin disable
  -- enrollment fleet-wide without rebuilding/reinstalling any kiosk.
  enrollment_enabled boolean not null default true,
  checkin_greeting_template text not null
    default 'Hello {name}, {time_greeting}! Welcome back to {institution}.',
  checkout_greeting_template text not null
    default 'Goodbye {name}, see you soon!',
  -- Set only via set_enrollment_pin() below -- never written or read as
  -- plaintext outside Postgres.
  enrollment_pin_hash text,
  updated_at timestamptz not null default now()
);

insert into public.kiosk_settings (id) values (true);

alter table public.kiosk_settings enable row level security;

create policy "kiosk_settings_admin_all"
  on public.kiosk_settings for all
  using (public.current_user_role() = 'admin')
  with check (public.current_user_role() = 'admin');

create policy "kiosk_settings_kiosk_select"
  on public.kiosk_settings for select
  using (public.current_user_role() = 'kiosk');

-- Per-kiosk PIN lockout bookkeeping, keyed off the calling kiosk's own
-- auth.uid() (same identity every other function in 0003_functions.sql
-- keys off of).
alter table public.profiles add column pin_failed_attempts int not null default 0;
alter table public.profiles add column pin_locked_until timestamptz;

-- Shared PIN-check logic used by both verify_enrollment_pin() (fast UI
-- feedback when the PIN pad is shown) and enroll_member() (the actual
-- authorization gate, re-checked server-side so a patched/rebuilt client
-- still can't create members without the real PIN). Not granted to
-- `authenticated` -- only callable from within the two SECURITY DEFINER
-- functions below.
create or replace function public._check_enrollment_pin(p_pin text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_hash text;
  v_locked_until timestamptz;
  v_ok boolean;
begin
  select pin_locked_until into v_locked_until
  from public.profiles where id = auth.uid();

  if v_locked_until is not null and v_locked_until > now() then
    return false;
  end if;

  select enrollment_pin_hash into v_hash from public.kiosk_settings where id = true;

  v_ok := v_hash is not null and v_hash = extensions.crypt(p_pin, v_hash);

  if v_ok then
    update public.profiles
      set pin_failed_attempts = 0, pin_locked_until = null
      where id = auth.uid();
  else
    update public.profiles
      set pin_failed_attempts = pin_failed_attempts + 1,
          pin_locked_until = case
            when pin_failed_attempts + 1 >= 5 then now() + interval '5 minutes'
            else pin_locked_until
          end
      where id = auth.uid();
  end if;

  return v_ok;
end;
$$;

-- Used by the kiosk's PIN pad for fast pass/fail feedback before showing
-- the enrollment UI. kiosk-only, like every other write-adjacent RPC here.
create or replace function public.verify_enrollment_pin(p_pin text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role text;
begin
  select role into v_role from public.profiles where id = auth.uid();
  if v_role is distinct from 'kiosk' then
    raise exception 'not authorized';
  end if;

  return public._check_enrollment_pin(p_pin);
end;
$$;

grant execute on function public.verify_enrollment_pin(text) to authenticated;

-- Creates a new member. Re-verifies p_pin itself rather than trusting that
-- the caller already passed the PIN pad -- see the comment on
-- _check_enrollment_pin above.
create or replace function public.enroll_member(
  p_pin text,
  p_full_name text,
  p_code text default null,
  p_group text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role text;
  v_settings_enabled boolean;
  v_employee_id uuid;
begin
  select role into v_role from public.profiles where id = auth.uid();
  if v_role is distinct from 'kiosk' then
    raise exception 'not authorized';
  end if;

  select enrollment_enabled into v_settings_enabled from public.kiosk_settings where id = true;
  if v_settings_enabled is distinct from true then
    raise exception 'enrollment disabled';
  end if;

  if not public._check_enrollment_pin(p_pin) then
    raise exception 'invalid or locked pin';
  end if;

  insert into public.employees (full_name, employee_code, department, created_by)
  values (p_full_name, p_code, p_group, auth.uid())
  returning id into v_employee_id;

  return v_employee_id;
end;
$$;

grant execute on function public.enroll_member(text, text, text, text) to authenticated;

-- Records one enrollment photo for a member created via enroll_member().
-- kiosk-only, mirroring record_face_embedding()'s pattern -- the kiosk
-- never gets a broad INSERT policy on employee_photos, only this narrow
-- function.
create or replace function public.record_member_photo(
  p_employee_id uuid,
  p_storage_path text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role text;
  v_photo_id uuid;
begin
  select role into v_role from public.profiles where id = auth.uid();
  if v_role is distinct from 'kiosk' then
    raise exception 'not authorized';
  end if;

  insert into public.employee_photos (employee_id, storage_path)
  values (p_employee_id, p_storage_path)
  returning id into v_photo_id;

  return v_photo_id;
end;
$$;

grant execute on function public.record_member_photo(uuid, text) to authenticated;

-- Admin-only: hashes and stores a new enrollment PIN. The plaintext PIN is
-- only ever handled inside this function call, never stored in the admin
-- panel itself.
create or replace function public.set_enrollment_pin(p_pin text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role text;
begin
  select role into v_role from public.profiles where id = auth.uid();
  if v_role is distinct from 'admin' then
    raise exception 'not authorized';
  end if;

  update public.kiosk_settings
    set enrollment_pin_hash = extensions.crypt(p_pin, extensions.gen_salt('bf')),
        updated_at = now()
    where id = true;
end;
$$;

grant execute on function public.set_enrollment_pin(text) to authenticated;

-- Storage: Storage has its own RLS layer separate from the functions
-- above, so the kiosk needs an explicit INSERT policy to upload enrollment
-- photos it captures itself (it already has a SELECT policy from
-- 0004_storage.sql, for downloading admin-captured photos during sync).
create policy "employee_photos_bucket_kiosk_insert"
  on storage.objects for insert
  with check (bucket_id = 'employee-photos' and public.current_user_role() = 'kiosk');
