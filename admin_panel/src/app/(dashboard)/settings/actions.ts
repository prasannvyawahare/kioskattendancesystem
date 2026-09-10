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

  const { error } = await supabase
    .from("kiosk_settings")
    .update({
      institution_name,
      member_label,
      checkin_greeting_template,
      checkout_greeting_template,
      voice_enabled,
      enrollment_enabled,
    })
    .eq("id", true);

  if (error) {
    redirect(`/settings?error=${encodeURIComponent(error.message)}`);
  }

  // Only rotates the PIN when a new one is actually typed -- leaving the
  // field blank on save must not wipe the existing PIN.
  const pin = String(formData.get("enrollment_pin") ?? "").trim();
  if (pin) {
    const { error: pinError } = await supabase.rpc("set_enrollment_pin", { p_pin: pin });
    if (pinError) {
      redirect(`/settings?error=${encodeURIComponent(pinError.message)}`);
    }
  }

  revalidatePath("/settings");
  redirect("/settings?saved=1");
}
