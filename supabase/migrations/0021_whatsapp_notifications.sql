-- Wires up the parent-notification channel that 0016_parent_contacts.sql
-- deferred ("a separate integration ... to be connected once a channel is
-- chosen"): Twilio's WhatsApp API. The actual send happens outside Postgres
-- entirely -- in the new supabase/functions/send-attendance-whatsapp Edge
-- Function, invoked by a Database Webhook on attendance_logs INSERT (a
-- dashboard-managed resource, not something a SQL migration can create; see
-- supabase/functions/send-attendance-whatsapp/README.md for that step).
-- This migration only adds what Postgres-side state that flow needs:
--   1. An admin-controlled kill switch, same pattern as enrollment_enabled.
--   2. A log table so delivery attempts/failures are visible somewhere
--      instead of silently disappearing into Edge Function logs no one
--      looks at.

alter table public.kiosk_settings
  add column whatsapp_notifications_enabled boolean not null default false;

-- One row per (attendance_logs row, parent contact) send attempt -- a
-- check-in/check-out with both mother_phone and father_phone on file
-- produces two rows, so one bad number doesn't obscure whether the other
-- send succeeded.
create table public.attendance_notification_log (
  id uuid primary key default gen_random_uuid(),
  attendance_log_id uuid not null references public.attendance_logs (id) on delete cascade,
  recipient text not null check (recipient in ('mother', 'father')),
  phone text not null,
  status text not null check (status in ('sent', 'failed', 'skipped')),
  error_message text,
  created_at timestamptz not null default now()
);

create index attendance_notification_log_attendance_log_id_idx
  on public.attendance_notification_log (attendance_log_id);

alter table public.attendance_notification_log enable row level security;

-- Written only by the Edge Function via the service-role key, which
-- bypasses RLS entirely -- these policies just govern what the admin panel
-- (as an authenticated admin user) is allowed to read.
create policy "attendance_notification_log_admin_select"
  on public.attendance_notification_log for select
  using (public.current_user_role() = 'admin');
