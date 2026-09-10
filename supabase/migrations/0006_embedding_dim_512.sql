-- Switches face_embeddings.embedding from vector(192) to vector(512).
--
-- The kiosk app originally targeted a 112x112/192-d MobileFaceNet model,
-- but the model actually available for testing is the standard FaceNet
-- (160x160 input, 512-d output) bundled in the `face_verification` pub
-- package. See kiosk_app/lib/services/embedding_service.dart, which was
-- updated to match (inputSize=160, embeddingSize=512).
--
-- Safe to run directly (no USING cast) only because face_embeddings was
-- empty at the time this was written -- a table with existing 192-d rows
-- would need those re-embedded, not cast.
alter table public.face_embeddings
  alter column embedding type vector(512);

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
