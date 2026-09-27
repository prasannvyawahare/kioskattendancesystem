-- Wires attendance_logs INSERT -> send-attendance-whatsapp Edge Function.
--
-- The README for that function (supabase/functions/send-attendance-whatsapp/
-- README.md) describes wiring this via Database → Webhooks in the
-- dashboard. That feature is itself just a thin UI over a trigger calling
-- pg_net's net.http_post() -- this migration creates that same trigger
-- directly, so the wiring is captured in version control/migration history
-- instead of living only as unreviewable dashboard state.
--
-- The shared secret below must match the send-attendance-whatsapp function's
-- ATTENDANCE_WEBHOOK_SECRET Edge Function secret (`supabase secrets set`) --
-- it's how the function authenticates the caller, since a trigger-fired
-- request carries no Supabase Auth JWT. If that secret is ever rotated,
-- this trigger function must be recreated with the new value.
create extension if not exists pg_net;

create or replace function public._notify_attendance_whatsapp()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform net.http_post(
    url := 'https://ssujawfxmpdkkzpqysdv.supabase.co/functions/v1/send-attendance-whatsapp',
    body := jsonb_build_object(
      'type', 'INSERT',
      'table', 'attendance_logs',
      'record', to_jsonb(new)
    ),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-webhook-secret', '1d861c9d864afde47ee0dfa1701817b3c297c367d7d00e1b3f7225830ee7840f'
    ),
    timeout_milliseconds := 10000
  );
  return new;
end;
$$;

create trigger attendance_logs_notify_whatsapp
  after insert on public.attendance_logs
  for each row execute function public._notify_attendance_whatsapp();
