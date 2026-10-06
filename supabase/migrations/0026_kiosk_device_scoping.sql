-- Per-class-section kiosk devices: a kiosk (profiles.role = 'kiosk') can now
-- be scoped to one standard/section (e.g. "12" / "A"), so a class teacher's
-- tablet only ever sees, embeds, enrolls, or marks attendance for students
-- in its own class. Devices are created from the admin panel's new
-- "Devices" page (service-role calls to auth.admin.createUser() + a
-- profiles insert -- no new RPC needed for that part, since the admin
-- panel's Postgres client already uses the service role key, which bypasses
-- RLS entirely).
--
-- assigned_standard/assigned_section are both nullable, and nullness is
-- meaningful, not just "not set yet":
--   * both null       -> unrestricted device (sees every class). This is
--     what every kiosk was, implicitly, before this migration -- so
--     existing single-shared-kiosk deployments keep working unchanged.
--   * standard set, section null -> every section of that standard.
--   * both set        -> exactly that class-section.
-- See kiosk_can_access() below for the matching rule, used everywhere a
-- kiosk reads or writes employee-scoped data.
alter table public.profiles
  add column assigned_standard text,
  add column assigned_section text,
  -- Human-readable device name shown in the admin panel's Devices list
  -- (e.g. "12th - A Tablet"). Distinct from full_name, which bootstrap.sql
  -- already uses for the same kind of label on hand-provisioned devices --
  -- this column exists so the admin panel doesn't have to overload
  -- full_name's meaning for devices it creates itself.
  add column device_label text;

-- Central scope check, reused by every kiosk-facing RLS policy and
-- SECURITY DEFINER function below so the matching rule only lives in one
-- place. SECURITY DEFINER (like current_user_role()) so it can read
-- profiles without being blocked by profiles' own RLS.
create or replace function public.kiosk_can_access(p_standard text, p_section text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_standard text;
  v_section text;
begin
  select assigned_standard, assigned_section into v_standard, v_section
  from public.profiles where id = auth.uid();

  if v_standard is null and v_section is null then
    return true;
  end if;

  if v_standard is not null and p_standard is distinct from v_standard then
    return false;
  end if;

  if v_section is not null and p_section is distinct from v_section then
    return false;
  end if;

  return true;
end;
$$;

grant execute on function public.kiosk_can_access(text, text) to authenticated;

-- employees/employee_photos/face_embeddings: the kiosk's existing SELECT
-- policies granted access to every active row regardless of class -- now
-- gated by kiosk_can_access() too. Admins are untouched (separate "_all"
-- policies already grant full access regardless of class).
drop policy "employees_kiosk_select_active" on public.employees;
create policy "employees_kiosk_select_active"
  on public.employees for select
  using (
    public.current_user_role() = 'kiosk'
    and is_active = true
    and public.kiosk_can_access(standard, section)
  );

drop policy "employee_photos_kiosk_select" on public.employee_photos;
create policy "employee_photos_kiosk_select"
  on public.employee_photos for select
  using (
    public.current_user_role() = 'kiosk'
    and exists (
      select 1 from public.employees e
      where e.id = employee_photos.employee_id
        and public.kiosk_can_access(e.standard, e.section)
    )
  );

drop policy "face_embeddings_kiosk_select" on public.face_embeddings;
create policy "face_embeddings_kiosk_select"
  on public.face_embeddings for select
  using (
    public.current_user_role() = 'kiosk'
    and exists (
      select 1 from public.employees e
      where e.id = face_embeddings.employee_id
        and public.kiosk_can_access(e.standard, e.section)
    )
  );

-- mark_attendance(): RLS doesn't apply inside SECURITY DEFINER functions,
-- so every write-adjacent RPC needs its own kiosk_can_access() check --
-- otherwise a class-scoped device that somehow obtained an out-of-scope
-- employee_id (e.g. from a stale cache, or a tampered client) could still
-- mark attendance for a student outside its class. Admins keep full access
-- (they call this RPC too, e.g. from a manual-correction flow), so the
-- check only applies when the caller is a kiosk. Reuses the existing
-- "unknown or inactive employee" error rather than a distinct one, so an
-- out-of-scope employee_id isn't distinguishable from a nonexistent one.
create or replace function public.mark_attendance(
  p_employee_id uuid,
  p_confidence real default null,
  p_mode text default 'both'
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role text;
  v_today date := (now() at time zone 'Asia/Kolkata')::date;
  v_check_in_at timestamptz;
  v_has_check_out boolean;
  v_result text;
  v_min_gap interval;
begin
  select role into v_role from public.profiles where id = auth.uid();
  if v_role is distinct from 'kiosk' and v_role is distinct from 'admin' then
    raise exception 'not authorized';
  end if;

  if p_mode not in ('both', 'check_in_only', 'check_out_only') then
    raise exception 'invalid mode: %', p_mode;
  end if;

  if not exists (
    select 1 from public.employees e
    where e.id = p_employee_id and e.is_active = true
      and (v_role = 'admin' or public.kiosk_can_access(e.standard, e.section))
  ) then
    raise exception 'unknown or inactive employee';
  end if;

  select (coalesce(min_scan_gap_minutes, 10) || ' minutes')::interval into v_min_gap
  from public.kiosk_settings where id = true;

  perform pg_advisory_xact_lock(hashtext(p_employee_id::text));

  select scanned_at into v_check_in_at
  from public.attendance_logs
  where employee_id = p_employee_id and event_date = v_today and event_type = 'check_in';

  select exists(
    select 1 from public.attendance_logs
    where employee_id = p_employee_id and event_date = v_today and event_type = 'check_out'
  ) into v_has_check_out;

  if p_mode = 'check_in_only' then
    if v_check_in_at is null then
      insert into public.attendance_logs (employee_id, event_type, event_date, confidence, kiosk_id)
      values (p_employee_id, 'check_in', v_today, p_confidence, auth.uid());
      v_result := 'check_in';
    else
      v_result := 'already_completed';
    end if;

  elsif p_mode = 'check_out_only' then
    if v_has_check_out then
      v_result := 'already_completed';
    else
      insert into public.attendance_logs (employee_id, event_type, event_date, confidence, kiosk_id)
      values (p_employee_id, 'check_out', v_today, p_confidence, auth.uid());
      v_result := 'check_out';
    end if;

  else -- 'both'
    if v_check_in_at is null then
      insert into public.attendance_logs (employee_id, event_type, event_date, confidence, kiosk_id)
      values (p_employee_id, 'check_in', v_today, p_confidence, auth.uid());
      v_result := 'check_in';
    elsif v_has_check_out then
      v_result := 'already_completed';
    elsif now() - v_check_in_at < v_min_gap then
      v_result := 'check_in';
    else
      insert into public.attendance_logs (employee_id, event_type, event_date, confidence, kiosk_id)
      values (p_employee_id, 'check_out', v_today, p_confidence, auth.uid());
      v_result := 'check_out';
    end if;
  end if;

  return v_result;
end;
$$;

grant execute on function public.mark_attendance(uuid, real, text) to authenticated;

-- sync_attendance_batch(): kiosk-only, so no admin bypass needed here --
-- an out-of-scope event is now rejected the same way an inactive/unknown
-- employee_id already was.
create or replace function public.sync_attendance_batch(p_events jsonb)
returns table (
  employee_id uuid,
  event_date date,
  event_type text,
  status text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role text;
  v_event record;
  v_max_backdate interval;
  v_skew interval;
  v_min_gap interval;
  v_checkin_at timestamptz;
begin
  select role into v_role from public.profiles where id = auth.uid();
  if v_role is distinct from 'kiosk' then
    raise exception 'not authorized';
  end if;

  select
    (coalesce(max_offline_backdate_days, 30) || ' days')::interval,
    (coalesce(clock_skew_tolerance_minutes, 10) || ' minutes')::interval,
    (coalesce(min_scan_gap_minutes, 10) || ' minutes')::interval
  into v_max_backdate, v_skew, v_min_gap
  from public.kiosk_settings where id = true;

  for v_event in
    select *
    from jsonb_to_recordset(p_events) as e(
      employee_id uuid,
      event_type text,
      event_date date,
      scanned_at timestamptz,
      confidence real
    )
  loop
    employee_id := v_event.employee_id;
    event_date := v_event.event_date;
    event_type := v_event.event_type;

    if v_event.event_type not in ('check_in', 'check_out')
       or v_event.scanned_at is null
       or v_event.event_date is null
       or not exists (
         select 1 from public.employees e
         where e.id = v_event.employee_id and e.is_active = true
           and public.kiosk_can_access(e.standard, e.section)
       )
       or v_event.scanned_at > now() + v_skew
       or v_event.scanned_at < now() - v_max_backdate
       or v_event.event_date <> (v_event.scanned_at at time zone 'Asia/Kolkata')::date
    then
      status := 'rejected';
      return next;
      continue;
    end if;

    if v_event.event_type = 'check_out' then
      select scanned_at into v_checkin_at
      from public.attendance_logs
      where employee_id = v_event.employee_id
        and event_date = v_event.event_date
        and event_type = 'check_in';

      if v_checkin_at is not null and v_event.scanned_at - v_checkin_at < v_min_gap then
        status := 'rejected';
        return next;
        continue;
      end if;
    end if;

    insert into public.attendance_logs
      (employee_id, event_type, event_date, scanned_at, confidence, kiosk_id)
    values
      (v_event.employee_id, v_event.event_type, v_event.event_date,
       v_event.scanned_at, v_event.confidence, auth.uid())
    on conflict on constraint attendance_logs_employee_id_event_date_event_type_key
    do nothing;

    status := case when found then 'inserted' else 'duplicate' end;
    return next;
  end loop;
end;
$$;

grant execute on function public.sync_attendance_batch(jsonb) to authenticated;

-- record_face_embedding() / mark_embedding_failed(): both kiosk-only.
-- Without this check, a class-scoped device's EnrollmentSyncService would
-- never have fetched an out-of-class pending employee in the first place
-- (now gated by the employees_kiosk_select_active RLS policy above), but
-- these RPCs take employee_id directly and are SECURITY DEFINER, so they
-- get the same belt-and-suspenders check as mark_attendance() above.
create or replace function public.record_face_embedding(
  p_employee_id uuid,
  p_photo_id uuid,
  p_embedding double precision[]
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role text;
  v_total_photos int;
  v_embedded_photos int;
begin
  select role into v_role from public.profiles where id = auth.uid();
  if v_role is distinct from 'kiosk' then
    raise exception 'not authorized';
  end if;

  if not exists (
    select 1 from public.employees e
    where e.id = p_employee_id and public.kiosk_can_access(e.standard, e.section)
  ) then
    raise exception 'not authorized';
  end if;

  insert into public.face_embeddings (employee_id, embedding, source_photo_id)
  values (p_employee_id, p_embedding::vector(512), p_photo_id);

  update public.employees set embedding_status = 'processing'
  where id = p_employee_id and embedding_status = 'pending';

  select count(*) into v_total_photos
  from public.employee_photos where employee_id = p_employee_id;

  select count(distinct source_photo_id) into v_embedded_photos
  from public.face_embeddings where employee_id = p_employee_id and source_photo_id is not null;

  if v_total_photos > 0 and v_embedded_photos >= v_total_photos then
    update public.employees set embedding_status = 'completed'
    where id = p_employee_id;
  end if;
end;
$$;

grant execute on function public.record_face_embedding(uuid, uuid, double precision[]) to authenticated;

create or replace function public.mark_embedding_failed(p_employee_id uuid)
returns void
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

  if not exists (
    select 1 from public.employees e
    where e.id = p_employee_id and public.kiosk_can_access(e.standard, e.section)
  ) then
    raise exception 'not authorized';
  end if;

  update public.employees set embedding_status = 'failed'
  where id = p_employee_id;
end;
$$;

grant execute on function public.mark_embedding_failed(uuid) to authenticated;

-- enroll_member() / update_member() / delete_member(): a class-scoped
-- device must not be able to enroll, edit, or delete a student outside its
-- own class -- not even by passing a different standard/section in the
-- call. Rather than rejecting a mismatched standard/section, enroll_member
-- and update_member silently force it to the device's own assignment
-- (ignoring whatever the client sent) when the device is scoped, so the
-- kiosk's own UI can just not show those fields for a scoped device without
-- the RPC call needing special-casing. An unrestricted device (both null)
-- keeps today's behavior of trusting whatever standard/section it's given.
create or replace function public.enroll_member(
  p_pin text,
  p_full_name text,
  p_code text default null,
  p_group text default null,
  p_email text default null,
  p_phone text default null,
  p_standard text default null,
  p_section text default null,
  p_mother_name text default null,
  p_mother_phone text default null,
  p_mother_email text default null,
  p_father_name text default null,
  p_father_phone text default null,
  p_father_email text default null
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
  v_assigned_standard text;
  v_assigned_section text;
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

  select assigned_standard, assigned_section into v_assigned_standard, v_assigned_section
  from public.profiles where id = auth.uid();

  if v_assigned_standard is not null or v_assigned_section is not null then
    p_standard := v_assigned_standard;
    p_section := v_assigned_section;
  end if;

  insert into public.employees (
    full_name, employee_code, department, email, phone, standard, section,
    mother_name, mother_phone, mother_email,
    father_name, father_phone, father_email,
    created_by
  )
  values (
    p_full_name, p_code, p_group, p_email, p_phone, p_standard, p_section,
    p_mother_name, p_mother_phone, p_mother_email,
    p_father_name, p_father_phone, p_father_email,
    auth.uid()
  )
  returning id into v_employee_id;

  return v_employee_id;
end;
$$;

grant execute on function public.enroll_member(
  text, text, text, text, text, text, text, text, text, text, text, text, text, text
) to authenticated;

create or replace function public.update_member(
  p_pin text,
  p_employee_id uuid,
  p_full_name text,
  p_code text default null,
  p_group text default null,
  p_email text default null,
  p_phone text default null,
  p_standard text default null,
  p_section text default null,
  p_mother_name text default null,
  p_mother_phone text default null,
  p_mother_email text default null,
  p_father_name text default null,
  p_father_phone text default null,
  p_father_email text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role text;
  v_settings_enabled boolean;
  v_assigned_standard text;
  v_assigned_section text;
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

  if not exists (
    select 1 from public.employees e
    where e.id = p_employee_id and public.kiosk_can_access(e.standard, e.section)
  ) then
    raise exception 'not authorized';
  end if;

  select assigned_standard, assigned_section into v_assigned_standard, v_assigned_section
  from public.profiles where id = auth.uid();

  if v_assigned_standard is not null or v_assigned_section is not null then
    p_standard := v_assigned_standard;
    p_section := v_assigned_section;
  end if;

  update public.employees
    set full_name = p_full_name,
        employee_code = p_code,
        department = p_group,
        email = p_email,
        phone = p_phone,
        standard = p_standard,
        section = p_section,
        mother_name = p_mother_name,
        mother_phone = p_mother_phone,
        mother_email = p_mother_email,
        father_name = p_father_name,
        father_phone = p_father_phone,
        father_email = p_father_email
    where id = p_employee_id;
end;
$$;

grant execute on function public.update_member(
  text, uuid, text, text, text, text, text, text, text, text, text, text, text, text, text
) to authenticated;

create or replace function public.delete_member(
  p_pin text,
  p_employee_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role text;
  v_settings_enabled boolean;
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

  if not exists (
    select 1 from public.employees e
    where e.id = p_employee_id and public.kiosk_can_access(e.standard, e.section)
  ) then
    raise exception 'not authorized';
  end if;

  delete from public.employees where id = p_employee_id;
end;
$$;

grant execute on function public.delete_member(text, uuid) to authenticated;
