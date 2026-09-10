"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

export async function deleteAttendanceLog(logId: string) {
  const supabase = createClient();
  await supabase.from("attendance_logs").delete().eq("id", logId);
  revalidatePath("/attendance");
}
