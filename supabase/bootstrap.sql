-- Run this manually, AFTER running the migrations, AFTER creating auth users
-- via Supabase Dashboard -> Authentication -> Add User:
--
--   1. One admin account, e.g. admin@yourorg.com (you'll log into the
--      Next.js admin panel with this).
--   2. One kiosk account PER PHYSICAL TABLET, e.g.
--      kiosk-frontdesk@yourorg.local, kiosk-gate2@yourorg.local, etc. Each
--      tablet is then built/run with its own --dart-define=KIOSK_EMAIL /
--      KIOSK_PASSWORD (see kiosk_app/README or CLAUDE.md).
--
-- Why per-device, not one shared kiosk login for the whole fleet: every
-- kiosk-scoped RPC (mark_attendance, sync_attendance_batch, enroll_member,
-- etc.) and the enrollment-PIN lockout in _check_enrollment_pin() are keyed
-- off auth.uid() -- the calling account's identity. With one account per
-- tablet:
--   * a lost/stolen/compromised tablet's credential can be revoked
--     individually (disable that one auth user) without re-provisioning
--     every other kiosk;
--   * enrollment-PIN lockout (5 failed attempts -> 5 minute lockout) is
--     scoped to the tablet that actually had the failed attempts, not
--     shared fleet-wide;
--   * attendance_logs.kiosk_id and any future auditing naturally
--     distinguishes which physical device recorded which event.
-- None of this requires a schema change -- it's purely how many auth users
-- and profiles rows you create below.

insert into public.profiles (id, role, full_name)
values (
  (select id from auth.users where email = 'admin@yourorg.com'),
  'admin',
  'Admin'
)
on conflict (id) do update set role = excluded.role;

-- Repeat this insert once per physical kiosk tablet, substituting its own
-- auth user email and a human-readable name for full_name (e.g. "Front Desk
-- Tablet", "Gate 2 Tablet") so attendance_logs.kiosk_id is meaningful later.
insert into public.profiles (id, role, full_name)
values (
  (select id from auth.users where email = 'kiosk-frontdesk@yourorg.local'),
  'kiosk',
  'Front Desk Tablet'
)
on conflict (id) do update set role = excluded.role;

-- insert into public.profiles (id, role, full_name)
-- values (
--   (select id from auth.users where email = 'kiosk-gate2@yourorg.local'),
--   'kiosk',
--   'Gate 2 Tablet'
-- )
-- on conflict (id) do update set role = excluded.role;
