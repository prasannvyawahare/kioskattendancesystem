# send-attendance-whatsapp

Notifies a student's parents (WhatsApp or SMS, via Twilio) every time
`attendance_logs` gets a new check-in/check-out row. See the header comment
in `index.ts`, `supabase/migrations/0021_whatsapp_notifications.sql`, and
`0023_notification_channel.sql` for what this does. This file covers setup
that can't be captured in a SQL migration (or, for the webhook wiring, that
*is* captured in a migration but is worth understanding).

**Current status on the `ssujawfxmpdkkzpqysdv` project:** deployed and wired
end-to-end (trigger → function → Twilio → `attendance_notification_log`),
verified against three different real Twilio account-level rejections. What
remains is entirely Twilio account setup, not code — see "Known blockers"
below.

## 1. Get Twilio credentials

From the [Twilio Console](https://console.twilio.com):

- **Account SID** and **Auth Token** — console home page.
- **WhatsApp-enabled sender** (`TWILIO_WHATSAPP_FROM`) — either the shared
  Sandbox number `whatsapp:+14155238886` (testing only; each recipient must
  first message it to join, and it only supports pre-approved templates —
  see "Known blockers") or your own approved WhatsApp Business sender.
- **SMS-capable sender** (`TWILIO_SMS_FROM`) — a plain Twilio phone number,
  no `whatsapp:` prefix, e.g. `+17372508034`.
- **WhatsApp Content Template SID** (`TWILIO_CONTENT_SID`, optional) — set
  this if you have a pre-approved WhatsApp template. Attendance pings are
  always business-initiated (a parent never messages first), so WhatsApp
  requires a template for every send — see "Known blockers".

## 2. Deploy the function

Run from the **repo root** (the parent of the `supabase/` folder), not from
inside `supabase/` — the CLI resolves `supabase/functions/...` relative to
your current directory, so running it from inside `supabase/` makes it look
for a nonexistent `supabase/supabase/functions/...` and fail with
`Entrypoint path does not exist`.

```sh
cd "/Users/prasannvyawahare/flutter_projects/kioskAttendace system"
supabase functions deploy send-attendance-whatsapp --no-verify-jwt
```

If you haven't already linked this repo to the project (`supabase link
--project-ref ssujawfxmpdkkzpqysdv`), do that first. The `WARNING: Docker is
not running` line is harmless — recent CLI versions bundle and deploy Edge
Functions remotely without a local Docker daemon.

`--no-verify-jwt` is required: this function is called by a Postgres
trigger, which carries no Supabase Auth JWT. Authorization instead comes
from the shared secret set in step 3.

## 3. Set Edge Function secrets

Never put these in `kiosk_app/.env`, `admin_panel/.env.local`, or any file
that ships to a client — the kiosk app in particular is an Android APK on
physical hardware, and anything in a `--dart-define`/bundled `.env` there is
extractable from the installed app. These secrets belong **only** in
Supabase's server-side Edge Function secrets:

```sh
supabase secrets set \
  TWILIO_ACCOUNT_SID=ACxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx \
  TWILIO_AUTH_TOKEN=your-twilio-auth-token \
  TWILIO_WHATSAPP_FROM=whatsapp:+14155238886 \
  TWILIO_SMS_FROM=+17372508034 \
  TWILIO_CONTENT_SID=HXxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx \
  ATTENDANCE_WEBHOOK_SECRET=$(openssl rand -hex 32)
```

`ATTENDANCE_WEBHOOK_SECRET` is a value you generate yourself — it's not a
Twilio credential. If you change it, you must also update the trigger in
step 4 to match. `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` don't need
setting — every Edge Function gets those automatically.

## 4. Wiring: `attendance_logs` INSERT → this function

Supabase's dashboard "Database Webhooks" feature is just a thin UI over a
Postgres trigger that calls `pg_net.http_post()`. Rather than leaving that
as unreviewable dashboard-only state, `migrations/0022_attendance_whatsapp_webhook_trigger.sql`
creates the same trigger directly — `attendance_logs_notify_whatsapp`,
firing `public._notify_attendance_whatsapp()` after every INSERT, which
POSTs to this function with the shared secret in an `x-webhook-secret`
header.

**If you ever rotate `ATTENDANCE_WEBHOOK_SECRET`**, you must `create or
replace function public._notify_attendance_whatsapp()` again with the new
value hardcoded in the trigger body — it's not read from an env var on the
Postgres side. Easiest way: re-run migration 0022's SQL (with the new
secret substituted in) via the SQL Editor or `apply_migration`.

If you'd rather use the dashboard's Webhooks UI instead of (or alongside)
this trigger, that's equally valid — just don't create both, or every
attendance row triggers two calls: **Database → Webhooks → Create a new
hook** → table `attendance_logs`, event Insert, POST to
`https://<project-ref>.supabase.co/functions/v1/send-attendance-whatsapp`,
header `x-webhook-secret` = your secret.

## 5. Turn it on

The function no-ops unless an admin picks a channel: **admin_panel →
Settings → "Notification channel"** (`kiosk_settings.parent_notification_channel`
— `disabled` / `whatsapp` / `sms`). Leave it `disabled` until Twilio is
confirmed working end-to-end (check `attendance_notification_log` in the DB
for `sent`/`failed`/`skipped` rows after a test scan).

## Known blockers (Twilio account state, not code)

Both channels are fully wired and will start working the moment the
relevant Twilio account setup is done — no further deploys needed.

- **WhatsApp**: a Trial account can only message numbers that are either
  Sandbox-joined or explicitly Verified Caller IDs, and outside an open
  24-hour session (which a parent never opens — they don't message first)
  every send requires a pre-approved Content Template (`TWILIO_CONTENT_SID`
  + `ContentVariables`, not free-form `Body`). Fix: upgrade off Trial, then
  register a WhatsApp Business sender and get a template approved.
- **SMS to Indian numbers**: Trial accounts get error `572006 — Invalid
  template name. Trial accounts can only use predefined SMS templates`,
  which is really India's DLT (Distributed Ledger Technology) regulation
  surfacing — TRAI requires commercial SMS content to Indian numbers to
  come from a DLT-registered template/sender. Fix: upgrade off Trial and
  complete Twilio's guided DLT registration flow.

## Testing without a physical kiosk scan

Either call `mark_attendance()` as the `kiosk`/`admin` role (it enforces
that role check itself):

```sql
select public.mark_attendance('<a real employees.id with mother_phone/father_phone set>'::uuid);
```

or invoke the function directly against an *existing* `attendance_logs` row
(safer than inserting a fake attendance record into real history):

```sh
curl -s -X POST "https://ssujawfxmpdkkzpqysdv.supabase.co/functions/v1/send-attendance-whatsapp" \
  -H "Content-Type: application/json" \
  -H "x-webhook-secret: <ATTENDANCE_WEBHOOK_SECRET>" \
  -d '{"type":"INSERT","table":"attendance_logs","record":{"id":"<existing attendance_logs.id>","employee_id":"<employees.id>","event_type":"check_in","event_date":"2026-09-27","scanned_at":"2026-09-27T16:23:19+00:00"}}'
```

Then check:

```sql
select * from public.attendance_notification_log order by created_at desc limit 5;
```
