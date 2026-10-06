"use server";

import { randomBytes } from "crypto";
import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";

/// Every action below uses the service-role client (createAdminClient),
/// which bypasses RLS entirely -- so each one re-checks the caller is a
/// logged-in admin itself rather than relying on profiles' RLS policies
/// the way the rest of the admin panel does. Server actions are reachable
/// as their own POST endpoints (not gated by (dashboard)/layout.tsx's
/// render-time redirect), so this check is the only thing actually
/// enforcing it here.
async function assertAdmin() {
  const supabase = createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) throw new Error("Not authenticated");

  const { data: profile } = await supabase.from("profiles").select("role").eq("id", user.id).single();
  if (profile?.role !== "admin") throw new Error("Not authorized");
}

function generateDeviceEmail(label: string) {
  const slug =
    label
      .toLowerCase()
      .trim()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/(^-+|-+$)/g, "") || "device";
  // kiosk.local is never actually sent mail to -- auth users created here
  // are confirmed server-side (email_confirm: true) so no verification
  // email ever needs to be deliverable.
  return `kiosk-${slug}-${randomBytes(3).toString("hex")}@kiosk.local`;
}

function generatePassword() {
  return randomBytes(15).toString("base64url");
}

export type DeviceCredentials = {
  id: string;
  email: string;
  password: string;
  deviceLabel: string;
  standard: string | null;
  section: string | null;
};

/// Creates a new kiosk device: a Supabase Auth user (service role only --
/// the anon key the rest of the app uses can't call auth.admin.*) plus its
/// profiles row, scoped to one class-section. Called directly from
/// AddDeviceDialog (not via a <form action> -- the generated password must
/// never round-trip through a URL/redirect) so it can hand the one-time
/// credentials back to be shown in a dismissable dialog; after that they're
/// not retrievable again (Supabase Auth only ever stores the salted hash --
/// see resetKioskDevicePassword for re-provisioning a device later).
export async function createKioskDevice(input: {
  deviceLabel: string;
  standard: string;
  section: string;
}): Promise<DeviceCredentials> {
  await assertAdmin();

  const deviceLabel = input.deviceLabel.trim();
  const standard = input.standard.trim() || null;
  const section = input.section.trim() || null;
  if (!deviceLabel) throw new Error("Device name is required");

  const supabaseAdmin = createAdminClient();
  const email = generateDeviceEmail(deviceLabel);
  const password = generatePassword();

  const { data: created, error: createError } = await supabaseAdmin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
  });
  if (createError || !created.user) {
    throw new Error(createError?.message ?? "Could not create device account");
  }

  const { error: profileError } = await supabaseAdmin.from("profiles").insert({
    id: created.user.id,
    role: "kiosk",
    device_label: deviceLabel,
    assigned_standard: standard,
    assigned_section: section,
  });
  if (profileError) {
    // Don't leave an orphaned Auth user with no profile row behind.
    await supabaseAdmin.auth.admin.deleteUser(created.user.id);
    throw new Error(profileError.message);
  }

  revalidatePath("/devices");
  return { id: created.user.id, email, password, deviceLabel, standard, section };
}

/// Re-provisioning path: the original password is never retrievable (only
/// its salted hash is stored), so "show the setup code again" actually
/// means issuing a fresh one. Safe to call anytime -- e.g. a tablet was
/// factory-reset and needs to be re-paired, or the admin just wants to
/// re-display it.
export async function resetKioskDevicePassword(deviceId: string): Promise<DeviceCredentials> {
  await assertAdmin();

  const supabaseAdmin = createAdminClient();
  const { data: profile, error: profileError } = await supabaseAdmin
    .from("profiles")
    .select("device_label, full_name, assigned_standard, assigned_section")
    .eq("id", deviceId)
    .eq("role", "kiosk")
    .single();
  if (profileError || !profile) throw new Error("Device not found");

  const password = generatePassword();
  const { data: updated, error: updateError } = await supabaseAdmin.auth.admin.updateUserById(deviceId, {
    password,
  });
  if (updateError || !updated.user?.email) {
    throw new Error(updateError?.message ?? "Could not reset credentials");
  }

  return {
    id: deviceId,
    email: updated.user.email,
    password,
    deviceLabel: profile.device_label ?? profile.full_name ?? "Device",
    standard: profile.assigned_standard,
    section: profile.assigned_section,
  };
}

/// Form-bound (no secret involved) -- reassigns which class-section a
/// device sees, without re-pairing it: the tablet keeps its existing
/// credentials and just starts seeing a different roster on its next poll
/// (RLS reads profiles.assigned_standard/section live, nothing is cached
/// server-side).
export async function updateKioskDeviceClass(formData: FormData) {
  await assertAdmin();

  const id = String(formData.get("id") ?? "");
  const deviceLabel = String(formData.get("device_label") ?? "").trim();
  const standard = String(formData.get("standard") ?? "").trim() || null;
  const section = String(formData.get("section") ?? "").trim() || null;
  if (!id || !deviceLabel) {
    redirect(`/devices?error=${encodeURIComponent("Device name is required")}`);
  }

  const supabaseAdmin = createAdminClient();
  const { error } = await supabaseAdmin
    .from("profiles")
    .update({ device_label: deviceLabel, assigned_standard: standard, assigned_section: section })
    .eq("id", id)
    .eq("role", "kiosk");
  if (error) {
    redirect(`/devices?error=${encodeURIComponent(error.message)}`);
  }

  revalidatePath("/devices");
  redirect("/devices?saved=1");
}

/// Deletes the device's Auth user outright (profiles row cascades via its
/// FK) -- irreversible, unlike the other actions here, so DeviceRow gates
/// this behind a confirm dialog before ever submitting the form.
export async function revokeKioskDevice(formData: FormData) {
  await assertAdmin();

  const id = String(formData.get("id") ?? "");
  if (!id) return;

  const supabaseAdmin = createAdminClient();
  const { error } = await supabaseAdmin.auth.admin.deleteUser(id);
  if (error) {
    redirect(`/devices?error=${encodeURIComponent(error.message)}`);
  }

  revalidatePath("/devices");
  redirect("/devices?saved=1");
}
