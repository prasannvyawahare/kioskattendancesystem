-- Lets the admin panel's dashboard subscribe to new attendance scans live.
-- postgres_changes subscriptions still respect each table's RLS SELECT
-- policy for the subscribing user, so this does not widen access.
alter publication supabase_realtime add table public.attendance_logs;
