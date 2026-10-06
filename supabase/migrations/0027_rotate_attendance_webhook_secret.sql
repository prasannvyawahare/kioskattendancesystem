-- Rotates the shared secret used to authenticate calls from the
-- attendance_logs trigger (see 0022_attendance_whatsapp_webhook_trigger.sql)
-- into the send-attendance-whatsapp Edge Function.
--
-- The previous value was committed in plaintext in migration 0022 and must
-- be treated as compromised. Before applying this migration, also rotate
-- the Edge Function's own copy of the secret:
--
--   supabase secrets set ATTENDANCE_WEBHOOK_SECRET=0247b040e409d799b44baf33049a1f878ca333ec0ff440dbc38b123a6b36c569
--
-- Both sides must match or the function will reject every call with 401.
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
      'x-webhook-secret', '0247b040e409d799b44baf33049a1f878ca333ec0ff440dbc38b123a6b36c569'
    ),
    timeout_milliseconds := 10000
  );
  return new;
end;
$$;
