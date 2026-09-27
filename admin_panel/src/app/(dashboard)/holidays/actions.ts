"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

export async function addHoliday(formData: FormData) {
  const supabase = createClient();

  const holiday_date = String(formData.get("holiday_date") ?? "").trim();
  const name = String(formData.get("name") ?? "").trim() || "Holiday";

  if (!/^\d{4}-\d{2}-\d{2}$/.test(holiday_date)) {
    redirect(`/holidays?error=${encodeURIComponent("Pick a valid holiday date")}`);
  }

  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { error } = await supabase
    .from("holidays")
    .upsert({ holiday_date, name, created_by: user?.id ?? null }, { onConflict: "holiday_date" });

  if (error) {
    redirect(`/holidays?error=${encodeURIComponent(error.message)}`);
  }

  revalidatePath("/holidays");
  revalidatePath("/attendance");
  revalidatePath("/attendance/register");
  revalidatePath("/reports");
  redirect("/holidays?saved=1");
}

export async function deleteHoliday(formData: FormData) {
  const supabase = createClient();
  const id = String(formData.get("id") ?? "");
  if (!id) return;

  const { error } = await supabase.from("holidays").delete().eq("id", id);
  if (error) {
    redirect(`/holidays?error=${encodeURIComponent(error.message)}`);
  }

  revalidatePath("/holidays");
  revalidatePath("/attendance");
  revalidatePath("/attendance/register");
  revalidatePath("/reports");
  redirect("/holidays?saved=1");
}
