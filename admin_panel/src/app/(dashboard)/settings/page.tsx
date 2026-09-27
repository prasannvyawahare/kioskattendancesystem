import { createClient } from "@/lib/supabase/server";
import { updateSettings } from "./actions";
import { SettingsToast } from "./SettingsToast";

export default async function SettingsPage({
  searchParams,
}: {
  searchParams: { error?: string; saved?: string };
}) {
  const supabase = createClient();
  const { data: settings } = await supabase.from("kiosk_settings").select("*").eq("id", true).single();

  return (
    <div className="max-w-2xl space-y-6">
      <div>
        <h1 className="text-lg font-semibold text-slate-900">Kiosk settings</h1>
        <p className="mt-1 text-sm text-slate-500">
          Controls what every kiosk shows and says, and whether kiosks are allowed to enroll new
          members on-device. Changes reach running kiosks within about a minute.
        </p>
      </div>

      {searchParams.error && (
        <p className="rounded-md bg-red-50 px-3 py-2 text-sm text-red-700">{searchParams.error}</p>
      )}
      <SettingsToast saved={searchParams.saved} />

      <form action={updateSettings} className="space-y-6">
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <TextField
            label="Institution name"
            name="institution_name"
            defaultValue={settings?.institution_name}
            hint='Used in greetings, e.g. "Welcome back to {institution}."'
          />
          <TextField
            label="Member label"
            name="member_label"
            defaultValue={settings?.member_label}
            hint='Kiosk-side wording only, e.g. "Employee" or "Student".'
          />
        </div>

        <TextArea
          label="Time In greeting"
          name="checkin_greeting_template"
          defaultValue={settings?.checkin_greeting_template}
        />
        <TextArea
          label="Time Out greeting"
          name="checkout_greeting_template"
          defaultValue={settings?.checkout_greeting_template}
        />
        <p className="text-xs text-slate-500">
          Placeholders: <code>{"{name}"}</code>, <code>{"{time_greeting}"}</code> (Good
          morning/afternoon/evening, computed on the kiosk), <code>{"{institution}"}</code>.
        </p>

        <div className="space-y-3 rounded-xl border border-slate-200 p-4">
          <Toggle
            label="Voice greeting"
            name="voice_enabled"
            defaultChecked={settings?.voice_enabled}
            hint="Speak the greeting aloud on Time In/Time Out. Off shows the result silently."
          />
          <Toggle
            label="On-device enrollment"
            name="enrollment_enabled"
            defaultChecked={settings?.enrollment_enabled}
            hint="Fleet-wide kill switch. Also requires the individual kiosk to be built with enrollment enabled."
          />
        </div>

        <div className="space-y-3 rounded-xl border border-slate-200 p-4">
          <div>
            <h2 className="text-sm font-semibold text-slate-900">Parent notifications</h2>
            <p className="text-xs text-slate-500">
              Notifies mother_phone/father_phone (via Twilio) on every Time In and Time Out.
              Requires the send-attendance-whatsapp Edge Function and its Database Webhook to be set
              up first -- see supabase/functions/send-attendance-whatsapp/README.md. WhatsApp needs
              either an opted-in Sandbox recipient or an approved Content Template on a non-trial
              Twilio account; SMS to Indian numbers needs DLT template registration on a non-trial
              account. Until one of those is set up, sends will fail (visible in
              attendance_notification_log) even with a channel selected here.
            </p>
          </div>
          <Select
            label="Notification channel"
            name="parent_notification_channel"
            defaultValue={settings?.parent_notification_channel ?? "disabled"}
            options={[
              { value: "disabled", label: "Disabled" },
              { value: "whatsapp", label: "WhatsApp" },
              { value: "sms", label: "SMS" },
            ]}
          />
        </div>

        <div className="space-y-3 rounded-xl border border-slate-200 p-4">
          <div>
            <h2 className="text-sm font-semibold text-slate-900">Kiosk timing</h2>
            <p className="text-xs text-slate-500">
              How long kiosks wait for the server before falling back to offline mode, how often
              they auto-sync/refresh in the background, and the minimum gap between a Time In and
              Time Out for the same person.
            </p>
          </div>
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <NumberField
              label="Online timeout (seconds)"
              name="online_timeout_seconds"
              defaultValue={settings?.online_timeout_seconds}
              hint="How long a scan/PIN check waits for the server before using the offline path."
            />
            <NumberField
              label="Min. Time In/Time Out gap (minutes)"
              name="min_scan_gap_minutes"
              defaultValue={settings?.min_scan_gap_minutes}
              hint="Also enforced server-side, so this can't be bypassed by an offline kiosk."
            />
            <NumberField
              label="Background sync interval (hours)"
              name="sync_interval_hours"
              defaultValue={settings?.sync_interval_hours}
              hint="How often a kiosk auto-syncs queued offline attendance."
            />
            <NumberField
              label="Roster refresh interval (seconds)"
              name="refresh_interval_seconds"
              defaultValue={settings?.refresh_interval_seconds}
              hint="How often a kiosk re-polls the employee list, member list, and this settings row."
            />
          </div>
        </div>

        <div className="space-y-1 rounded-xl border border-slate-200 p-4">
          <label htmlFor="enrollment_pin" className="text-sm font-medium text-slate-700">
            Enrollment PIN
          </label>
          <input
            id="enrollment_pin"
            name="enrollment_pin"
            type="password"
            autoComplete="off"
            minLength={4}
            placeholder={settings?.enrollment_pin_hash ? "•••••• (unchanged)" : "Not set"}
            className="w-full rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-slate-500"
          />
          <p className="text-xs text-slate-500">
            Leave blank to keep the current PIN. Entering a value here replaces it -- the previous
            PIN is not shown, it&apos;s stored as a hash. Must be at least 4 characters.
          </p>
        </div>

        <button
          type="submit"
          className="rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-500"
        >
          Save settings
        </button>
      </form>
    </div>
  );
}

function TextField({
  label,
  name,
  defaultValue,
  hint,
}: {
  label: string;
  name: string;
  defaultValue?: string | null;
  hint?: string;
}) {
  return (
    <div className="space-y-1">
      <label htmlFor={name} className="text-sm font-medium text-slate-700">
        {label}
      </label>
      <input
        id={name}
        name={name}
        type="text"
        defaultValue={defaultValue ?? ""}
        className="w-full rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-slate-500"
      />
      {hint && <p className="text-xs text-slate-500">{hint}</p>}
    </div>
  );
}

function NumberField({
  label,
  name,
  defaultValue,
  hint,
}: {
  label: string;
  name: string;
  defaultValue?: number | null;
  hint?: string;
}) {
  return (
    <div className="space-y-1">
      <label htmlFor={name} className="text-sm font-medium text-slate-700">
        {label}
      </label>
      <input
        id={name}
        name={name}
        type="number"
        min={1}
        step={1}
        defaultValue={defaultValue ?? undefined}
        className="w-full rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-slate-500"
      />
      {hint && <p className="text-xs text-slate-500">{hint}</p>}
    </div>
  );
}

function TextArea({
  label,
  name,
  defaultValue,
}: {
  label: string;
  name: string;
  defaultValue?: string | null;
}) {
  return (
    <div className="space-y-1">
      <label htmlFor={name} className="text-sm font-medium text-slate-700">
        {label}
      </label>
      <textarea
        id={name}
        name={name}
        rows={2}
        defaultValue={defaultValue ?? ""}
        className="w-full rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-slate-500"
      />
    </div>
  );
}

function Select({
  label,
  name,
  defaultValue,
  options,
  hint,
}: {
  label: string;
  name: string;
  defaultValue?: string | null;
  options: { value: string; label: string }[];
  hint?: string;
}) {
  return (
    <div className="space-y-1">
      <label htmlFor={name} className="text-sm font-medium text-slate-700">
        {label}
      </label>
      <select
        id={name}
        name={name}
        defaultValue={defaultValue ?? options[0]?.value}
        className="w-full rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-slate-500"
      >
        {options.map((option) => (
          <option key={option.value} value={option.value}>
            {option.label}
          </option>
        ))}
      </select>
      {hint && <p className="text-xs text-slate-500">{hint}</p>}
    </div>
  );
}

function Toggle({
  label,
  name,
  defaultChecked,
  hint,
}: {
  label: string;
  name: string;
  defaultChecked?: boolean | null;
  hint?: string;
}) {
  return (
    <div className="flex items-start gap-3">
      <input
        id={name}
        name={name}
        type="checkbox"
        defaultChecked={defaultChecked ?? true}
        className="mt-1 h-4 w-4 rounded border-slate-300"
      />
      <label htmlFor={name} className="flex-1">
        <span className="block text-sm font-medium text-slate-700">{label}</span>
        {hint && <span className="block text-xs text-slate-500">{hint}</span>}
      </label>
    </div>
  );
}
