"use client";

import { useState, type MouseEvent } from "react";
import {
  resetKioskDevicePassword,
  revokeKioskDevice,
  updateKioskDeviceClass,
  type DeviceCredentials,
} from "./actions";
import { CredentialsReveal } from "./CredentialsReveal";

export type DeviceListItem = {
  id: string;
  device_label: string | null;
  full_name: string | null;
  assigned_standard: string | null;
  assigned_section: string | null;
  email: string | null;
  lastSignInAt: string | null;
};

export function DeviceRow({ device }: { device: DeviceListItem }) {
  const [editing, setEditing] = useState(false);
  const [resetting, setResetting] = useState(false);
  const [resetError, setResetError] = useState<string | null>(null);
  const [credentials, setCredentials] = useState<DeviceCredentials | null>(null);

  const label = device.device_label ?? device.full_name ?? "Unnamed device";
  const classLabel = device.assigned_standard
    ? `${device.assigned_standard}${device.assigned_section ? ` - ${device.assigned_section}` : ""}`
    : "All classes";

  async function handleReset() {
    setResetting(true);
    setResetError(null);
    try {
      const creds = await resetKioskDevicePassword(device.id);
      setCredentials(creds);
    } catch (err) {
      setResetError(err instanceof Error ? err.message : "Could not reset credentials");
    } finally {
      setResetting(false);
    }
  }

  function handleRevokeClick(event: MouseEvent<HTMLButtonElement>) {
    if (!confirm(`Revoke "${label}"? This immediately signs the tablet out and cannot be undone.`)) {
      event.preventDefault();
    }
  }

  return (
    <li className="space-y-3 py-4">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <p className="font-medium text-slate-900">{label}</p>
          <p className="text-xs text-slate-500">{device.email ?? "no email on record"}</p>
          <p className="text-xs text-slate-400">
            {device.lastSignInAt
              ? `Last seen ${new Date(device.lastSignInAt).toLocaleString()}`
              : "Never signed in"}
          </p>
        </div>
        <span className="rounded-full bg-violet-50 px-3 py-1 text-xs font-medium text-violet-700">
          {classLabel}
        </span>
      </div>

      <div className="flex flex-wrap gap-2 text-xs">
        <button
          type="button"
          onClick={() => setEditing((v) => !v)}
          className="rounded-md border border-slate-300 px-2.5 py-1.5 font-medium text-slate-600 hover:bg-slate-50"
        >
          {editing ? "Cancel" : "Reassign class"}
        </button>
        <button
          type="button"
          onClick={handleReset}
          disabled={resetting}
          className="rounded-md border border-slate-300 px-2.5 py-1.5 font-medium text-slate-600 hover:bg-slate-50 disabled:opacity-40"
        >
          {resetting ? "Resetting..." : "Reset credentials"}
        </button>
        <form action={revokeKioskDevice}>
          <input type="hidden" name="id" value={device.id} />
          <button
            type="submit"
            onClick={handleRevokeClick}
            className="rounded-md border border-red-200 px-2.5 py-1.5 font-medium text-red-600 hover:bg-red-50"
          >
            Revoke
          </button>
        </form>
      </div>

      {resetError && <p className="text-xs text-red-600">{resetError}</p>}

      {editing && (
        <form
          action={updateKioskDeviceClass}
          className="flex flex-wrap items-end gap-2 rounded-lg border border-slate-200 bg-slate-50 p-3 text-xs"
        >
          <input type="hidden" name="id" value={device.id} />
          <LabeledInput label="Device name" name="device_label" defaultValue={label} required />
          <LabeledInput
            label="Standard"
            name="standard"
            defaultValue={device.assigned_standard ?? ""}
            placeholder="blank = all"
          />
          <LabeledInput
            label="Section"
            name="section"
            defaultValue={device.assigned_section ?? ""}
            placeholder="blank = all"
          />
          <button
            type="submit"
            className="rounded-md bg-indigo-600 px-3 py-1.5 font-medium text-white hover:bg-indigo-500"
          >
            Save
          </button>
        </form>
      )}

      {credentials && (
        <CredentialsReveal credentials={credentials} onClose={() => setCredentials(null)} />
      )}
    </li>
  );
}

function LabeledInput({
  label,
  name,
  defaultValue,
  placeholder,
  required,
}: {
  label: string;
  name: string;
  defaultValue?: string;
  placeholder?: string;
  required?: boolean;
}) {
  return (
    <div className="space-y-1">
      <label htmlFor={name} className="block font-medium text-slate-600">
        {label}
      </label>
      <input
        id={name}
        name={name}
        defaultValue={defaultValue}
        placeholder={placeholder}
        required={required}
        className="rounded-md border border-slate-300 px-2 py-1.5"
      />
    </div>
  );
}
