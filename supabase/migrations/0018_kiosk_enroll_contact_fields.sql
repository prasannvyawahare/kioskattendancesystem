-- On-device enrollment (AddMemberScreen) only ever collected name/code/
-- group, while the admin-panel registration form (register-employee-form.tsx)
-- also captures email/phone and mother/father contact details (added to
-- public.employees by 0016_parent_contacts.sql). This migration brings
-- enroll_member()/update_member() up to parity so a member added or edited
-- directly on the kiosk can carry the same fields as one registered via the
-- admin panel.
--
-- Adding parameters changes each function's identity (name + arg types), so
-- the old 4/5-arg overloads are dropped rather than left dangling -- both
-- call sites (kiosk_app/lib/services/supabase_backend.dart) are updated in
-- the same change to always pass every field.

drop function if exists public.enroll_member(text, text, text, text);

create function public.enroll_member(
  p_pin text,
  p_full_name text,
  p_code text default null,
  p_group text default null,
  p_email text default null,
  p_phone text default null,
  p_mother_name text default null,
  p_mother_phone text default null,
  p_mother_email text default null,
  p_father_name text default null,
  p_father_phone text default null,
  p_father_email text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role text;
  v_settings_enabled boolean;
  v_employee_id uuid;
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

  insert into public.employees (
    full_name, employee_code, department, email, phone,
    mother_name, mother_phone, mother_email,
    father_name, father_phone, father_email,
    created_by
  )
  values (
    p_full_name, p_code, p_group, p_email, p_phone,
    p_mother_name, p_mother_phone, p_mother_email,
    p_father_name, p_father_phone, p_father_email,
    auth.uid()
  )
  returning id into v_employee_id;

  return v_employee_id;
end;
$$;

grant execute on function public.enroll_member(
  text, text, text, text, text, text, text, text, text, text, text, text
) to authenticated;

drop function if exists public.update_member(text, uuid, text, text, text);

create function public.update_member(
  p_pin text,
  p_employee_id uuid,
  p_full_name text,
  p_code text default null,
  p_group text default null,
  p_email text default null,
  p_phone text default null,
  p_mother_name text default null,
  p_mother_phone text default null,
  p_mother_email text default null,
  p_father_name text default null,
  p_father_phone text default null,
  p_father_email text default null
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
        department = p_group,
        email = p_email,
        phone = p_phone,
        mother_name = p_mother_name,
        mother_phone = p_mother_phone,
        mother_email = p_mother_email,
        father_name = p_father_name,
        father_phone = p_father_phone,
        father_email = p_father_email
    where id = p_employee_id;
end;
$$;

grant execute on function public.update_member(
  text, uuid, text, text, text, text, text, text, text, text, text, text, text
) to authenticated;
