-- Makes several previously-hardcoded kiosk timing constants admin-managed
-- from the same kiosk_settings singleton row the greeting templates etc.
-- already live in:
--
--   * online_timeout_seconds -- how long the kiosk app waits for
--     mark_attendance()/verify_enrollment_pin() to answer before falling
--     back to its offline path (kiosk_app/lib/services/attendance_service.dart,
--     pin_verification_service.dart).
--   * min_scan_gap_minutes -- the minimum gap between a check-in and
--     check-out for the same person (was hardcoded `interval '10 minutes'`
--     in mark_attendance() as of 0012_min_checkout_gap.sql; also mirrored
--     client-side in AttendanceDecisionEngine for the offline decision).
--   * sync_interval_hours -- how often SyncService auto-syncs queued
--     offline attendance in the background.
--   * refresh_interval_seconds -- how often the kiosk re-polls the
--     employee roster, member list, and this settings row itself.
--
-- The kiosk-side timers become admin-configurable but still self-govern
-- app-side (nothing here changes how the kiosk *decides* -- see
-- AttendanceDecisionEngine -- just what durations it uses). Only
-- min_scan_gap_minutes needs a change to mark_attendance() itself, since
-- that's the one value also enforced authoritatively in Postgres.

alter table public.kiosk_settings
  add column online_timeout_seconds integer not null default 5
    check (online_timeout_seconds > 0),
  add column min_scan_gap_minutes integer not null default 10
    check (min_scan_gap_minutes > 0),
  add column sync_interval_hours integer not null default 8
    check (sync_interval_hours > 0),
  add column refresh_interval_seconds integer not null default 60
    check (refresh_interval_seconds > 0);

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

  if not exists (select 1 from public.employees where id = p_employee_id and is_active = true) then
    raise exception 'unknown or inactive employee';
  end if;

  -- Admin-configurable (see this migration's header comment); falls back
  -- to 10 minutes if the settings row is somehow missing, matching the
  -- previous hardcoded default.
  select (coalesce(min_scan_gap_minutes, 10) || ' minutes')::interval into v_min_gap
  from public.kiosk_settings where id = true;

  -- Serializes concurrent scans for the same employee (e.g. two kiosks, or
  -- two frames both triggering a match) so the check-in/check-out decision
  -- below can't race. The unique constraint on attendance_logs is a
  -- backstop, not the primary guard.
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
    -- Deliberately doesn't require a prior check-in row: a check-out-only
    -- kiosk is presumably the only touchpoint that day.
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
      -- Still within the minimum gap since check-in: treat as a duplicate
      -- check-in scan rather than checking the person out.
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
