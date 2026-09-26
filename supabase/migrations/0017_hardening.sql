-- Hardening pass addressing a security review of 0001-0016:
--
--   1. sync_attendance_batch() previously trusted client-supplied
--      scanned_at/event_date verbatim with zero plausibility checks, unlike
--      mark_attendance() (advisory-locked, min-gap-enforced). A kiosk
--      credential (compiled into the APK via --dart-define, extractable
--      from a decompiled/rooted tablet) could otherwise be used to insert
--      arbitrarily backdated or future-dated attendance rows for any active
--      employee, bypassing every rule mark_attendance() enforces. This
--      migration adds three checks per event, all resulting in a
--      'rejected' status row (never an exception -- one bad event in a
--      batch must not abort the rest of the kiosk's queue):
--        a. scanned_at can't be further in the future than a small clock-
--           skew tolerance (kiosk_settings.clock_skew_tolerance_minutes).
--        b. scanned_at can't be older than a bounded backdate window
--           (kiosk_settings.max_offline_backdate_days) -- long enough to
--           survive a real multi-day outage, short enough to bound the
--           blast radius of a stolen credential.
--        c. event_date must actually match scanned_at's Asia/Kolkata date
--           (same day boundary mark_attendance() uses) -- catches
--           mismatched/spoofed pairs.
--        d. a check_out is gap-checked against any check_in already on
--           file for that employee/day (kiosk_settings.min_scan_gap_minutes,
--           same column mark_attendance() reads) -- blocks fabricated
--           instant check-in/check-out pairs. Deliberately does NOT require
--           a prior check_in to exist at all: check-out-only kiosks
--           (mark_attendance()'s p_mode='check_out_only') legitimately
--           write check_out with no matching check_in that day.
--      This still does not re-run the full check-in/check-out decision
--      (see 0013's header comment for why: the decision was already made
--      client-side, offline, by AttendanceDecisionEngine, and re-deciding
--      against server-side state at sync time would retroactively
--      reinterpret history) -- it only bounds how implausible an
--      already-decided event is allowed to be.
--
--   2. attendance_logs gets an index on event_date alone:
--      fetch_today_attendance() (0013) filters by event_date with no
--      supporting index (the existing composite index is
--      (employee_id, event_date)), so every kiosk reconnect/restart was a
--      sequential scan that only gets worse as history accumulates.
--
--   3. set_enrollment_pin() gets a minimum-length check. Previously any
--      non-empty string, including a single character, was accepted both
--      client- and server-side for a PIN that gates on-device member
--      enrollment/edit/delete.
--
--   4. The kiosk gets a narrow DELETE policy on its own enrollment photos
--      in the employee-photos bucket, so kiosk-initiated member deletion
--      (delete_member(), 0008) can clean up the photos it's deleting
--      instead of leaving them orphaned in Storage forever (DB rows cascade
--      via FK, but storage blobs never did). Scoped identically to the
--      kiosk's existing INSERT/SELECT policies on this bucket -- no new
--      trust granted beyond "kiosk can manage employee-photos objects it
--      already has select/insert on".
--
-- Note on the "single shared kiosk credential" finding from the same
-- review: bootstrap.sql already documents per-device kiosk accounts as the
-- recommended path (a lost/stolen tablet's credential can then be revoked
-- individually, and PIN lockout in _check_enrollment_pin(), keyed on
-- auth.uid(), naturally becomes per-device instead of fleet-wide) -- that's
-- an operational/provisioning fix, not a schema change; see the rewritten
-- bootstrap.sql for the actual fix.

alter table public.kiosk_settings
  add column max_offline_backdate_days integer not null default 30
    check (max_offline_backdate_days > 0),
  add column clock_skew_tolerance_minutes integer not null default 10
    check (clock_skew_tolerance_minutes > 0);

create index attendance_logs_event_date_idx on public.attendance_logs (event_date);

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
         select 1 from public.employees
         where id = v_event.employee_id and is_active = true
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

  if p_pin is null or length(p_pin) < 4 then
    raise exception 'pin must be at least 4 characters';
  end if;

  update public.kiosk_settings
    set enrollment_pin_hash = extensions.crypt(p_pin, extensions.gen_salt('bf')),
        updated_at = now()
    where id = true;
end;
$$;

grant execute on function public.set_enrollment_pin(text) to authenticated;

create policy "employee_photos_bucket_kiosk_delete"
  on storage.objects for delete
  using (bucket_id = 'employee-photos' and public.current_user_role() = 'kiosk');
