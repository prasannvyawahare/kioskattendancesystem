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
          label="Check-in greeting"
          name="checkin_greeting_template"
          defaultValue={settings?.checkin_greeting_template}
        />
        <TextArea
          label="Check-out greeting"
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
            hint="Speak the greeting aloud on check-in/check-out. Off shows the result silently."
          />
          <Toggle
            label="On-device enrollment"
            name="enrollment_enabled"
            defaultChecked={settings?.enrollment_enabled}
            hint="Fleet-wide kill switch. Also requires the individual kiosk to be built with enrollment enabled."
          />
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
            placeholder={settings?.enrollment_pin_hash ? "•••••• (unchanged)" : "Not set"}
            className="w-full rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-slate-500"
          />
          <p className="text-xs text-slate-500">
            Leave blank to keep the current PIN. Entering a value here replaces it -- the previous
            PIN is not shown, it&apos;s stored as a hash.
          </p>
        </div>

        <button
          type="submit"
          className="rounded-md bg-slate-900 px-4 py-2 text-sm font-medium text-white"
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
