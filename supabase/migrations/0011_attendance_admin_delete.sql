-- attendance_logs previously only granted admins SELECT (0002_rls.sql) --
-- writes went exclusively through mark_attendance(). The admin panel now
-- needs to delete a mistaken/duplicate scan, so add DELETE for admins only;
-- INSERT/UPDATE stay closed off (mark_attendance() remains the only writer
-- of new rows).
create policy "attendance_logs_admin_delete"
  on public.attendance_logs for delete
  using (public.current_user_role() = 'admin');
