-- record_face_embedding() is SECURITY DEFINER with `set search_path = ''`
-- (same as every function in this schema, for security), but its
-- `p_embedding::vector(512)` cast used a bare, unqualified `vector` type
-- name. With an empty search_path, Postgres can't resolve `vector` because
-- pgvector is installed in the `extensions` schema on this project -- the
-- same class of bug already fixed for crypt()/gen_salt() in
-- 0007_kiosk_enrollment.sql. This broke every embedding write (both the
-- admin-panel sync path and on-device enrollment go through this one
-- function), which is why employees got stuck on embedding_status =
-- 'pending' indefinitely.

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

  insert into public.face_embeddings (employee_id, embedding, source_photo_id)
  values (p_employee_id, p_embedding::extensions.vector(512), p_photo_id);

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
