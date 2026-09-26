-- Offline-first support for the kiosk app. Three changes:
--
--   1. mark_attendance() gains a p_mode param so the device-local
--      attendance-mode setting (Both / Check-in only / Check-out only --
--      see kiosk_app/lib/models/attendance_mode.dart) is respected on the
--      *online* path too, not just offline. This setting is intentionally
--      device-local (stored only in the kiosk's sqflite db, never in
--      kiosk_settings), so there's nothing to read here -- the kiosk just
--      tells us which mode it's currently in.
--
--   2. sync_attendance_batch() lets a kiosk push events it decided and
--      queued while offline (via kiosk_app's AttendanceDecisionEngine, a
--      Dart mirror of this file's decision logic). It's a dumb, deduped
--      insert of already-decided events -- it does NOT re-run the
--      check-in/check-out branches below, because by the time an offline
--      event reaches here the decision already reflects whatever mode was
--      active on the device at scan time; re-deciding against the mode
--      active at sync time would retroactively reinterpret history.
--
--   3. fetch_today_attendance() lets a kiosk hydrate its local
--      attendance_state cache with today's check-ins/check-outs it didn't
--      personally witness (e.g. after a mid-day restart), so an offline
--      stretch right after a restart can't double-check-in someone the
--      server already has a check-in for.

-- CREATE OR REPLACE can't change a function's parameter count/types (that
-- produces a distinct, overloaded function rather than replacing this
-- one) -- drop the old 2-arg signature first so there's exactly one
-- mark_attendance() left, matching the grant below.
drop function if exists public.mark_attendance(uuid, real);

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
  v_min_gap interval := interval '10 minutes';
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

-- Batch-inserts previously offline-queued attendance events. p_events is a
-- jsonb array of {employee_id, event_type, event_date, scanned_at,
-- confidence}. Returns one row per input event with a terminal status
-- ('inserted' | 'duplicate' | 'rejected') so the kiosk knows every row is
-- safe to drop from its local queue.
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
begin
  select role into v_role from public.profiles where id = auth.uid();
  if v_role is distinct from 'kiosk' then
    raise exception 'not authorized';
  end if;

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
    if v_event.event_type not in ('check_in', 'check_out')
       or not exists (
         select 1 from public.employees
         where id = v_event.employee_id and is_active = true
       )
    then
      employee_id := v_event.employee_id;
      event_date := v_event.event_date;
      event_type := v_event.event_type;
      status := 'rejected';
      return next;
      continue;
    end if;

    insert into public.attendance_logs
      (employee_id, event_type, event_date, scanned_at, confidence, kiosk_id)
    values
      (v_event.employee_id, v_event.event_type, v_event.event_date,
       v_event.scanned_at, v_event.confidence, auth.uid())
    -- Named by constraint, not by column list: this function's OUT
    -- parameters are also named employee_id/event_date/event_type (that's
    -- what RETURNS TABLE(...) does under the hood), so an `on conflict
    -- (employee_id, event_date, event_type)` column list is ambiguous
    -- between the table's columns and this function's own variables --
    -- caught by testing this migration directly (see
    -- 0014_fix_sync_attendance_batch_conflict.sql).
    on conflict on constraint attendance_logs_employee_id_event_date_event_type_key
    do nothing;

    employee_id := v_event.employee_id;
    event_date := v_event.event_date;
    event_type := v_event.event_type;
    status := case when found then 'inserted' else 'duplicate' end;
    return next;
  end loop;
end;
$$;

grant execute on function public.sync_attendance_batch(jsonb) to authenticated;

-- Today's attendance_logs rows (same Asia/Kolkata day boundary as
-- mark_attendance), for a kiosk to reconcile its local attendance_state
-- cache with check-ins/check-outs it didn't personally witness.
create or replace function public.fetch_today_attendance()
returns table (
  employee_id uuid,
  event_type text,
  scanned_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role text;
begin
  select role into v_role from public.profiles where id = auth.uid();
  if v_role is distinct from 'kiosk' and v_role is distinct from 'admin' then
    raise exception 'not authorized';
  end if;

  return query
    select al.employee_id, al.event_type, al.scanned_at
    from public.attendance_logs al
    where al.event_date = (now() at time zone 'Asia/Kolkata')::date;
end;
$$;

grant execute on function public.fetch_today_attendance() to authenticated;
