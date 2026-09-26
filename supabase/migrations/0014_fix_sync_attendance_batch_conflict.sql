-- Fixes a bug in sync_attendance_batch() (0013_offline_sync.sql), caught by
-- testing it directly: `on conflict (employee_id, event_date, event_type)`
-- is ambiguous inside this function, because its own RETURNS TABLE OUT
-- parameters are named employee_id/event_date/event_type too -- Postgres
-- can't tell whether the conflict target list means the table's columns or
-- this function's variables, and errors with "column reference ... is
-- ambiguous". Naming the conflict by its underlying constraint instead of
-- a column list sidesteps the collision entirely.
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
