-- Kiosk-side edit/delete for members created via enroll_member() -- same
-- PIN-gated pattern: the server re-checks p_pin itself rather than trusting
-- that the caller already passed the PIN pad, so a patched/rebuilt client
-- still can't rename or remove a member without the real PIN. Also honors
-- kiosk_settings.enrollment_enabled, same as enroll_member, since edit/
-- delete are part of the same on-device member-management surface an admin
-- disables with that toggle. See
-- kiosk_app/lib/screens/member_list_screen.dart for the client side.

create or replace function public.update_member(
  p_pin text,
  p_employee_id uuid,
  p_full_name text,
  p_code text default null,
  p_group text default null
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

  update public.employees
    set full_name = p_full_name,
        employee_code = p_code,
        department = p_group
    where id = p_employee_id;
end;
$$;

grant execute on function public.update_member(text, uuid, text, text, text) to authenticated;

-- Cascades to employee_photos and face_embeddings via their FK `on delete
-- cascade` (0001_schema.sql) -- storage blobs in the employee-photos bucket
-- are not cleaned up here, only the DB rows referencing them.
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

  delete from public.employees where id = p_employee_id;
end;
$$;

grant execute on function public.delete_member(text, uuid) to authenticated;
