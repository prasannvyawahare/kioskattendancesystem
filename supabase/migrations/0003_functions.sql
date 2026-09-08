-- Business-logic functions. These are SECURITY DEFINER so the kiosk role
-- can be granted EXECUTE without needing broad INSERT/UPDATE policies on
-- attendance_logs / employees / face_embeddings -- see 0002_rls.sql.
--
-- Why the admin panel never calls record_face_embedding(): embeddings from
-- two different models/runtimes are not comparable via cosine similarity.
-- The admin panel (browser) only uploads raw photos; the kiosk (Flutter) is
-- the only thing that ever runs the embedding model, both at enrollment
-- time (via this function) and at recognition time, so there is exactly
-- one model/runtime/preprocessing pipeline in the whole system.

-- Atomically decides check_in vs check_out vs already_completed for a scan.
-- NOTE: the day boundary is computed in a fixed timezone -- adjust
-- 'Asia/Kolkata' below to match wherever your kiosk is physically deployed.
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
  v_has_check_in boolean;
  v_has_check_out boolean;
  v_result text;
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

  select
    exists(
      select 1 from public.attendance_logs
      where employee_id = p_employee_id and event_date = v_today and event_type = 'check_in'
    ),
    exists(
      select 1 from public.attendance_logs
      where employee_id = p_employee_id and event_date = v_today and event_type = 'check_out'
    )
  into v_has_check_in, v_has_check_out;

  if not v_has_check_in then
    insert into public.attendance_logs (employee_id, event_type, event_date, confidence, kiosk_id)
    values (p_employee_id, 'check_in', v_today, p_confidence, auth.uid());
    v_result := 'check_in';
  elsif not v_has_check_out then
    insert into public.attendance_logs (employee_id, event_type, event_date, confidence, kiosk_id)
    values (p_employee_id, 'check_out', v_today, p_confidence, auth.uid());
    v_result := 'check_out';
  else
    v_result := 'already_completed';
  end if;

  return v_result;
end;
$$;

grant execute on function public.mark_attendance(uuid, real) to authenticated;

-- Called once per enrollment photo by the kiosk's enrollment sync service.
-- Flips employees.embedding_status to 'completed' once every photo for
-- that employee has produced an embedding.
create or replace function public.record_face_embedding(
  p_employee_id uuid,
  p_photo_id uuid,
  -- double precision[] rather than `vector` directly: PostgREST's RPC
  -- layer reliably coerces JSON arrays into standard Postgres array types,
  -- but has no defined JSON cast for pgvector's `vector` type. Casting to
  -- vector happens inside this function instead.
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

  insert into public.face_embeddings (employee_id, embedding, source_photo_id)
  values (p_employee_id, p_embedding::vector(192), p_photo_id);

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

-- Called by the kiosk if a photo can't be turned into an embedding (e.g.
-- no face detected in any enrollment photo), so the admin panel can show
-- the employee needs to be re-photographed instead of hanging on "pending".
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

  update public.employees set embedding_status = 'failed'
  where id = p_employee_id;
end;
$$;

grant execute on function public.mark_embedding_failed(uuid) to authenticated;
