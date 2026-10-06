"use client";

import { useState } from "react";
import type { DeviceCredentials } from "./actions";

/// Shown once right after createKioskDevice/resetKioskDevicePassword
/// returns -- this is the only moment the plaintext password exists
/// anywhere outside the tablet itself (Supabase Auth only ever keeps the
/// salted hash), so closing this dialog without saving it means running
/// resetKioskDevicePassword again to get a new one.
///
/// "Setup code" is just email+password base64-encoded together, so the
/// kiosk's first-run screen can accept a single pasted blob instead of two
/// separately-typed fields -- see kiosk_app/lib/screens/device_setup_screen.dart.
export function CredentialsReveal({
  credentials,
  onClose,
}: {
  credentials: DeviceCredentials;
  onClose: () => void;
}) {
  const setupCode =
    typeof window !== "undefined"
      ? btoa(JSON.stringify({ email: credentials.email, password: credentials.password }))
      : "";

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4">
      <div className="w-full max-w-md rounded-xl bg-white p-6 shadow-xl">
        <h2 className="text-base font-semibold text-slate-900">
          {credentials.deviceLabel} is ready to pair
        </h2>
        <p className="mt-1 text-sm text-slate-500">
          Enter this on the tablet&apos;s <span className="font-medium">first-run setup screen</span>.
          The password is shown only this once -- if you lose it, use &quot;Reset credentials&quot; on
          this device to get a new one.
        </p>

        <div className="mt-4 space-y-3">
          <CopyField label="Setup code (paste this on the tablet)" value={setupCode} mono big />
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
            <CopyField label="Device email" value={credentials.email} mono />
            <CopyField label="Device password" value={credentials.password} mono />
          </div>
          {(credentials.standard || credentials.section) && (
            <p className="text-xs text-slate-500">
              Scoped to class{" "}
              <span className="font-medium text-slate-700">
                {credentials.standard ?? "-"}
                {credentials.section ? ` - ${credentials.section}` : ""}
              </span>
              .
            </p>
          )}
        </div>

        <button
          type="button"
          onClick={onClose}
          className="mt-6 w-full rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-500"
        >
          I&apos;ve saved these -- close
        </button>
      </div>
    </div>
  );
}

function CopyField({
  label,
  value,
  mono,
  big,
}: {
  label: string;
  value: string;
  mono?: boolean;
  big?: boolean;
}) {
  const [copied, setCopied] = useState(false);

  async function copy() {
    try {
      await navigator.clipboard.writeText(value);
      setCopied(true);
      setTimeout(() => setCopied(false), 1500);
    } catch {
      // Clipboard API unavailable (e.g. insecure context) -- the field's
      // own text is still selectable/copyable by hand.
    }
  }

  return (
    <div className="space-y-1">
      <label className="block text-xs font-medium text-slate-600">{label}</label>
      <div className="flex items-center gap-2">
        <input
          readOnly
          value={value}
          onFocus={(e) => e.currentTarget.select()}
          className={`w-full truncate rounded-md border border-slate-300 px-2 py-1.5 text-slate-900 ${
            mono ? "font-mono" : ""
          } ${big ? "text-xs" : "text-sm"}`}
        />
        <button
          type="button"
          onClick={copy}
          className="shrink-0 rounded-md border border-slate-300 px-2 py-1.5 text-xs font-medium text-slate-600 hover:bg-slate-50"
        >
          {copied ? "Copied" : "Copy"}
        </button>
      </div>
    </div>
  );
}
