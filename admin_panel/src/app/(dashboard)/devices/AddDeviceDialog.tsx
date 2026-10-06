"use client";

import { useState, type FormEvent } from "react";
import { createKioskDevice, type DeviceCredentials } from "./actions";
import { CredentialsReveal } from "./CredentialsReveal";

export function AddDeviceDialog() {
  const [open, setOpen] = useState(false);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [credentials, setCredentials] = useState<DeviceCredentials | null>(null);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setPending(true);
    setError(null);

    const formData = new FormData(event.currentTarget);
    try {
      const created = await createKioskDevice({
        deviceLabel: String(formData.get("device_label") ?? ""),
        standard: String(formData.get("standard") ?? ""),
        section: String(formData.get("section") ?? ""),
      });
      setOpen(false);
      setCredentials(created);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not create device");
    } finally {
      setPending(false);
    }
  }

  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        className="rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-500"
      >
        Add device
      </button>

      {open && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4">
          <div className="w-full max-w-sm rounded-xl bg-white p-6 shadow-xl">
            <h2 className="text-base font-semibold text-slate-900">Add kiosk device</h2>
            <p className="mt-1 text-sm text-slate-500">
              Creates a device identity for one tablet. Leave class/section blank for a device that
              should see every student (e.g. a front-desk kiosk).
            </p>

            <form onSubmit={handleSubmit} className="mt-4 space-y-3">
              <Field label="Device name" name="device_label" placeholder="e.g. 12th - A Tablet" required />
              <div className="grid grid-cols-2 gap-3">
                <Field label="Standard" name="standard" placeholder="e.g. 12" />
                <Field label="Section" name="section" placeholder="e.g. A" />
              </div>

              {error && <p className="text-sm text-red-600">{error}</p>}

              <div className="flex justify-end gap-2 pt-2">
                <button
                  type="button"
                  onClick={() => setOpen(false)}
                  className="rounded-md px-3 py-2 text-sm font-medium text-slate-600 hover:bg-slate-100"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={pending}
                  className="rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-500 disabled:opacity-40"
                >
                  {pending ? "Creating..." : "Create device"}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {credentials && (
        <CredentialsReveal credentials={credentials} onClose={() => setCredentials(null)} />
      )}
    </>
  );
}

function Field({
  label,
  name,
  placeholder,
  required,
}: {
  label: string;
  name: string;
  placeholder?: string;
  required?: boolean;
}) {
  return (
    <div className="space-y-1">
      <label htmlFor={name} className="text-xs font-medium text-slate-600">
        {label}
      </label>
      <input
        id={name}
        name={name}
        placeholder={placeholder}
        required={required}
        className="w-full rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-slate-500"
      />
    </div>
  );
}
