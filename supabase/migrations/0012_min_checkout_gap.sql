-- Requires a minimum gap between check-in and check-out so that someone who
-- simply lingers in front of the kiosk camera (chatting, waiting for the
-- next person, etc.) doesn't get auto-checked-out moments after checking in.
-- The kiosk-side debounce in AttendanceService only protects against
-- back-to-back frames a few seconds apart; it does not protect against a
-- person re-triggering a scan a minute or two later while still in frame,
-- so the real guard belongs here, in the atomic decision function.
create or replace function public.mark_attendance(
  p_employee_id uuid,
  p_confidence real default null
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
  v_min_gap interval := interval '10 minutes';
begin
  select role into v_role from public.profiles where id = auth.uid();
  if v_role is distinct from 'kiosk' and v_role is distinct from 'admin' then
    raise exception 'not authorized';
  end if;

  if not exists (select 1 from public.employees where id = p_employee_id and is_active = true) then
    raise exception 'unknown or inactive employee';
  end if;

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

  return v_result;
end;
$$;

grant execute on function public.mark_attendance(uuid, real) to authenticated;
