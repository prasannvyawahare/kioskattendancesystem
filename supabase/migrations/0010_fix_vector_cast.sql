-- 0008's fix (`p_embedding::extensions.vector(512)`) assumed pgvector was
-- installed in the `extensions` schema, same as pgcrypto -- it isn't
-- (likely `public`, since 0001_schema.sql's `create extension if not
-- exists vector;` ran with no SCHEMA clause). Rather than guess again,
-- sidestep schema resolution entirely: pgvector registers an assignment
-- cast from double precision[] to vector, so Postgres will coerce
-- p_embedding into the `embedding vector(512)` column automatically from
-- the column's own catalog type -- no `vector` type name needs to appear,
-- resolved or not, anywhere in this function body.

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
  values (p_employee_id, p_embedding, p_photo_id);

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
