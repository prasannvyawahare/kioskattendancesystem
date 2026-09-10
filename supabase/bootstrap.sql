-- Run this manually, AFTER running the migrations, AFTER creating two auth
-- users via Supabase Dashboard -> Authentication -> Add User:
--
--   1. An admin account, e.g. admin@yourorg.com   (you'll log into the
--      Next.js admin panel with this)
--   2. A kiosk device account (the Flutter app signs in with this once at
--      startup -- see kiosk_app/.env). Currently p@g.com for this project's
--      kiosk device.
--
-- Looks each account up by email rather than requiring you to copy UUIDs
-- out of the dashboard -- edit the email literals below to match your
-- actual admin/kiosk accounts before running.

insert into public.profiles (id, role, full_name)
values (
  (select id from auth.users where email = 'admin@yourorg.com'),
  'admin',
  'Admin'
)
on conflict (id) do update set role = excluded.role;

insert into public.profiles (id, role, full_name)
values (
  (select id from auth.users where email = 'p@g.com'),
  'kiosk',
  'Kiosk Device 1'
)
on conflict (id) do update set role = excluded.role;

-- To provision an additional kiosk device later (recommended over sharing
-- one kiosk credential across many tablets, so a lost/stolen device can be
-- revoked individually): create another auth user (kiosk-2@yourorg.local)
-- and insert() another profiles row the same way, substituting its email
-- in the lookup above.
