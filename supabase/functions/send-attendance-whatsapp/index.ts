// Triggered by a Supabase Database Webhook on attendance_logs INSERT (see
// README.md in this folder for the one-time dashboard wiring -- Database
// Webhooks aren't something a SQL migration can create).
//
// Looks up the scanned employee's parent contacts
// (employees.mother_phone/father_phone, see
// supabase/migrations/0016_parent_contacts.sql) and notifies each one on
// file via Twilio, over whichever channel the admin picked in Settings
// (kiosk_settings.parent_notification_channel: 'disabled' | 'whatsapp' |
// 'sms' -- supabase/migrations/0023_notification_channel.sql). Every
// attempt is recorded in attendance_notification_log so failures are
// visible instead of silently vanishing into function logs.
//
// Deliberately dependency-free (plain fetch against PostgREST + the Twilio
// REST API) -- this function does nothing complex enough to need the
// supabase-js SDK.

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const WEBHOOK_SECRET = Deno.env.get("ATTENDANCE_WEBHOOK_SECRET")!;
const TWILIO_ACCOUNT_SID = Deno.env.get("TWILIO_ACCOUNT_SID")!;
const TWILIO_AUTH_TOKEN = Deno.env.get("TWILIO_AUTH_TOKEN")!;
// Twilio's WhatsApp-enabled sender, in "whatsapp:+1415..." form -- see
// README.md for sandbox vs. approved-sender setup.
const TWILIO_WHATSAPP_FROM = Deno.env.get("TWILIO_WHATSAPP_FROM") ?? "";
// Plain Twilio phone number for the 'sms' channel, no "whatsapp:" prefix
// (e.g. "+17372508034"). Unlike WhatsApp, SMS has no session-window or
// template requirement -- Body sends freely at any time -- so this is the
// simpler channel to get working first.
const TWILIO_SMS_FROM = Deno.env.get("TWILIO_SMS_FROM") ?? "";
// Attendance pings are always business-initiated (a parent never messages
// first), so WhatsApp requires a pre-approved Content Template for every
// send -- freeform Body only works inside a 24h session the parent opened,
// which never happens here. Set to a Content SID (from the Sandbox's
// built-in templates while testing, or your own approved template once
// registered) to send via contentSid/contentVariables instead of Body. Only
// used for the 'whatsapp' channel; irrelevant to 'sms'.
const TWILIO_CONTENT_SID = Deno.env.get("TWILIO_CONTENT_SID") ?? "";

// Same day/time boundary mark_attendance() uses
// (supabase/migrations/0003_functions.sql) -- keeps the wording in the
// message consistent with what the kiosk itself decided.
const KIOSK_TIME_ZONE = "Asia/Kolkata";

const REST_HEADERS = {
  apikey: SERVICE_ROLE_KEY,
  Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
  "Content-Type": "application/json",
};

type NotificationChannel = "disabled" | "whatsapp" | "sms";

interface AttendanceLogRecord {
  id: string;
  employee_id: string;
  event_type: "check_in" | "check_out";
  event_date: string;
  scanned_at: string;
}

interface WebhookPayload {
  type: "INSERT" | "UPDATE" | "DELETE";
  table: string;
  record: AttendanceLogRecord;
}

interface EmployeeContact {
  full_name: string;
  mother_name: string | null;
  mother_phone: string | null;
  father_name: string | null;
  father_phone: string | null;
}

// Accepts "+919876543210", but also tolerates the spaces/dashes/parens a
// human might have typed into the admin panel's phone field -- strips them
// before validating, rather than rejecting otherwise-good numbers outright.
// Existing employees.mother_phone/father_phone data was captured as bare
// 10-digit local numbers (e.g. "9588672331", "09588672331") with no country
// code, so a bare 10-digit number (optionally with a leading trunk "0") is
// treated as India (+91) -- this kiosk system hardcodes Asia/Kolkata
// throughout (see mark_attendance()), so that's a safe default. Revisit if
// this deployment ever serves a non-Indian number.
function normalizePhone(raw: string): string | null {
  const stripped = raw.replace(/[\s\-()]/g, "");
  if (/^\+[1-9]\d{6,14}$/.test(stripped)) return stripped;

  const bare = stripped.replace(/^0/, "");
  if (/^[6-9]\d{9}$/.test(bare)) return `+91${bare}`;

  return null;
}

async function logAttempt(
  attendanceLogId: string,
  recipient: "mother" | "father",
  channel: "whatsapp" | "sms",
  phone: string,
  status: "sent" | "failed" | "skipped",
  errorMessage?: string,
) {
  await fetch(`${SUPABASE_URL}/rest/v1/attendance_notification_log`, {
    method: "POST",
    headers: REST_HEADERS,
    body: JSON.stringify({
      attendance_log_id: attendanceLogId,
      recipient,
      channel,
      phone,
      status,
      error_message: errorMessage ?? null,
    }),
  });
}

async function sendTwilioMessage(form: URLSearchParams): Promise<{ ok: boolean; error?: string }> {
  const credentials = btoa(`${TWILIO_ACCOUNT_SID}:${TWILIO_AUTH_TOKEN}`);
  const response = await fetch(
    `https://api.twilio.com/2010-04-01/Accounts/${TWILIO_ACCOUNT_SID}/Messages.json`,
    {
      method: "POST",
      headers: {
        Authorization: `Basic ${credentials}`,
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: form,
    },
  );

  if (response.ok) return { ok: true };
  const detail = await response.text();
  return { ok: false, error: `Twilio ${response.status}: ${detail.slice(0, 500)}` };
}

function sendWhatsApp(toPhone: string, body: string, contentVariables: Record<string, string>) {
  const form = TWILIO_CONTENT_SID
    ? new URLSearchParams({
        From: TWILIO_WHATSAPP_FROM,
        To: `whatsapp:${toPhone}`,
        ContentSid: TWILIO_CONTENT_SID,
        ContentVariables: JSON.stringify(contentVariables),
      })
    : new URLSearchParams({
        From: TWILIO_WHATSAPP_FROM,
        To: `whatsapp:${toPhone}`,
        Body: body,
      });
  return sendTwilioMessage(form);
}

function sendSms(toPhone: string, body: string) {
  const form = new URLSearchParams({
    From: TWILIO_SMS_FROM,
    To: toPhone,
    Body: body,
  });
  return sendTwilioMessage(form);
}

// One recipient's send + log-write, isolated so a bad mother_phone can't
// prevent the father_phone send (or vice versa) from being attempted.
async function notifyRecipient(
  attendanceLogId: string,
  recipient: "mother" | "father",
  channel: "whatsapp" | "sms",
  rawPhone: string | null,
  message: string,
  contentVariables: Record<string, string>,
) {
  if (!rawPhone) return;

  const phone = normalizePhone(rawPhone);
  if (!phone) {
    await logAttempt(attendanceLogId, recipient, channel, rawPhone, "skipped", "not a valid E.164 phone number");
    return;
  }

  const result = channel === "whatsapp"
    ? await sendWhatsApp(phone, message, contentVariables)
    : await sendSms(phone, message);

  await logAttempt(attendanceLogId, recipient, channel, phone, result.ok ? "sent" : "failed", result.error);
}

// contentVariables (used for the 'whatsapp' channel only, when
// TWILIO_CONTENT_SID is set) maps to the Sandbox's built-in "Appointment
// Reminders" template ("Your appointment is coming up on {{1}} at {{2}}")
// -- its wording doesn't actually fit attendance, it's only there to prove
// the send pipeline end-to-end before a real approved template exists. Once
// you register a custom template (see README.md), rename these keys/values
// to match its actual placeholders and update `message` (used for SMS, and
// for WhatsApp's freeform/no-ContentSid fallback path) to match your
// template's real wording so the two stay in sync.
function buildMessage(
  studentName: string,
  eventType: "check_in" | "check_out",
  scannedAt: string,
): { message: string; contentVariables: Record<string, string> } {
  const when = new Date(scannedAt);
  const date = when.toLocaleDateString("en-IN", { timeZone: KIOSK_TIME_ZONE, day: "2-digit", month: "short", year: "numeric" });
  const time = when.toLocaleTimeString("en-IN", { timeZone: KIOSK_TIME_ZONE, hour: "2-digit", minute: "2-digit", hour12: true });

  const action = eventType === "check_in" ? "checked IN" : "checked OUT";
  return {
    message: `${studentName} has ${action} at ${time} on ${date}.`,
    contentVariables: {
      "1": `${studentName} has ${action}`,
      "2": `${time} on ${date}`,
    },
  };
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("method not allowed", { status: 405 });
  }

  // Database Webhooks carry no user JWT (there's no authenticated user --
  // it's a Postgres trigger firing), so this function has to be deployed
  // with --no-verify-jwt and instead check a shared secret set as a custom
  // header on the webhook itself. See README.md.
  if (req.headers.get("x-webhook-secret") !== WEBHOOK_SECRET) {
    return new Response("unauthorized", { status: 401 });
  }

  const payload = (await req.json()) as WebhookPayload;

  if (payload.table !== "attendance_logs" || payload.type !== "INSERT") {
    return new Response(JSON.stringify({ skipped: "not an attendance_logs insert" }), { status: 200 });
  }

  const record = payload.record;

  const settingsResponse = await fetch(
    `${SUPABASE_URL}/rest/v1/kiosk_settings?id=eq.true&select=parent_notification_channel`,
    { headers: REST_HEADERS },
  );
  const [settings] = await settingsResponse.json();
  const channel = (settings?.parent_notification_channel ?? "disabled") as NotificationChannel;

  if (channel === "disabled") {
    return new Response(JSON.stringify({ skipped: "parent_notification_channel is disabled" }), { status: 200 });
  }

  const employeeResponse = await fetch(
    `${SUPABASE_URL}/rest/v1/employees?id=eq.${record.employee_id}` +
      `&select=full_name,mother_name,mother_phone,father_name,father_phone`,
    { headers: REST_HEADERS },
  );
  const [employee] = (await employeeResponse.json()) as EmployeeContact[];

  if (!employee) {
    return new Response(JSON.stringify({ skipped: "employee not found" }), { status: 200 });
  }

  const { message, contentVariables } = buildMessage(employee.full_name, record.event_type, record.scanned_at);

  await Promise.all([
    notifyRecipient(record.id, "mother", channel, employee.mother_phone, message, contentVariables),
    notifyRecipient(record.id, "father", channel, employee.father_phone, message, contentVariables),
  ]);

  return new Response(JSON.stringify({ ok: true, channel }), { status: 200 });
});
