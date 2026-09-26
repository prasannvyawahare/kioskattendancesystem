"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

export async function updateSettings(formData: FormData) {
  const supabase = createClient();

  const institution_name = String(formData.get("institution_name") ?? "").trim();
  const member_label = String(formData.get("member_label") ?? "").trim();
  const checkin_greeting_template = String(formData.get("checkin_greeting_template") ?? "").trim();
  const checkout_greeting_template = String(
    formData.get("checkout_greeting_template") ?? "",
  ).trim();
  const voice_enabled = formData.get("voice_enabled") === "on";
  const enrollment_enabled = formData.get("enrollment_enabled") === "on";

  // Kiosk timing knobs -- positive-integer inputs, falling back to the
  // column's own default (via the check constraint) rather than trusting
  // unvalidated form input if something odd comes through.
  const positiveInt = (name: string, fallback: number) => {
    const n = Number(formData.get(name));
    return Number.isInteger(n) && n > 0 ? n : fallback;
  };
  const online_timeout_seconds = positiveInt("online_timeout_seconds", 5);
  const min_scan_gap_minutes = positiveInt("min_scan_gap_minutes", 10);
  const sync_interval_hours = positiveInt("sync_interval_hours", 8);
  const refresh_interval_seconds = positiveInt("refresh_interval_seconds", 60);

  const { error } = await supabase
    .from("kiosk_settings")
    .update({
      institution_name,
      member_label,
      checkin_greeting_template,
      checkout_greeting_template,
      voice_enabled,
      enrollment_enabled,
      online_timeout_seconds,
      min_scan_gap_minutes,
      sync_interval_hours,
      refresh_interval_seconds,
    })
    .eq("id", true);

  if (error) {
    redirect(`/settings?error=${encodeURIComponent(error.message)}`);
  }

  // Only rotates the PIN when a new one is actually typed -- leaving the
  // field blank on save must not wipe the existing PIN.
  const pin = String(formData.get("enrollment_pin") ?? "").trim();
  if (pin) {
    // Mirrors the >=4-char check set_enrollment_pin() enforces server-side
    // (supabase/migrations/0017_hardening.sql) -- checked here too so a
    // short PIN gets a friendly message instead of a raw Postgres error.
    if (pin.length < 4) {
      redirect(`/settings?error=${encodeURIComponent("PIN must be at least 4 characters")}`);
    }
    const { error: pinError } = await supabase.rpc("set_enrollment_pin", { p_pin: pin });
    if (pinError) {
      const message = pinError.message.includes("pin must be at least")
        ? "PIN must be at least 4 characters"
        : pinError.message;
      redirect(`/settings?error=${encodeURIComponent(message)}`);
    }
  }

  revalidatePath("/settings");
  redirect("/settings?saved=1");
}
