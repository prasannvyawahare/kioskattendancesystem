-- Replaces the WhatsApp-only kill switch from 0021_whatsapp_notifications.sql
-- with a channel picker: WhatsApp requires either an opted-in Sandbox
-- recipient or an approved Content Template and a non-trial Twilio account
-- (see supabase/functions/send-attendance-whatsapp/README.md), which isn't
-- always available, so SMS -- no session window, no template, freeform
-- Body at any time -- is a simpler first channel to get working.
alter table public.kiosk_settings
  add column parent_notification_channel text not null default 'disabled'
    check (parent_notification_channel in ('disabled', 'whatsapp', 'sms'));

update public.kiosk_settings
  set parent_notification_channel = case when whatsapp_notifications_enabled then 'whatsapp' else 'disabled' end;

alter table public.kiosk_settings drop column whatsapp_notifications_enabled;

alter table public.attendance_notification_log
  add column channel text not null default 'whatsapp'
    check (channel in ('whatsapp', 'sms'));
