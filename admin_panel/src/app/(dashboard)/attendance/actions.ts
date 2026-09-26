"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

export async function deleteAttendanceLog(logId: string) {
  const supabase = createClient();
  const { error } = await supabase.from("attendance_logs").delete().eq("id", logId);

  if (error) {
    redirect(`/attendance?error=${encodeURIComponent(error.message)}`);
  }

  revalidatePath("/attendance");
}
