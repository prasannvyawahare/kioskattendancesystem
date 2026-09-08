-- Run this manually, AFTER running the migrations, AFTER creating two auth
-- users via Supabase Dashboard -> Authentication -> Add User:
--
--   1. An admin account, e.g. admin@yourorg.com   (you'll log into the
--      Next.js admin panel with this)
--   2. A kiosk device account, e.g. kiosk@yourorg.local  (the Flutter app
--      signs in with this once at startup -- see kiosk_app README)
--
-- Copy each user's UUID from the Dashboard's user list (or
-- `select id, email from auth.users;`) and substitute below.

insert into public.profiles (id, role, full_name)
values ('<ADMIN_AUTH_USER_UUID>', 'admin', 'Admin')
on conflict (id) do update set role = excluded.role;

insert into public.profiles (id, role, full_name)
values ('<KIOSK_AUTH_USER_UUID>', 'kiosk', 'Kiosk Device 1')
on conflict (id) do update set role = excluded.role;

-- To provision an additional kiosk device later (recommended over sharing
-- one kiosk credential across many tablets, so a lost/stolen device can be
-- revoked individually): create another auth user (kiosk-2@yourorg.local)
-- and insert() another profiles row the same way.
