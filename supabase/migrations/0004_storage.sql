-- Storage bucket for employee enrollment photos.
-- Path convention used by the admin panel when uploading: {employee_id}/{photo_id}.jpg

insert into storage.buckets (id, name, public)
values ('employee-photos', 'employee-photos', false)
on conflict (id) do nothing;

create policy "employee_photos_bucket_admin_all"
  on storage.objects for all
  using (bucket_id = 'employee-photos' and public.current_user_role() = 'admin')
  with check (bucket_id = 'employee-photos' and public.current_user_role() = 'admin');

create policy "employee_photos_bucket_kiosk_select"
  on storage.objects for select
  using (bucket_id = 'employee-photos' and public.current_user_role() = 'kiosk');
