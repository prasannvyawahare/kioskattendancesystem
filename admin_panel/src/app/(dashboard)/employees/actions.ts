"use server";

import { randomUUID } from "crypto";
import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

export async function registerEmployee(formData: FormData) {
  const supabase = createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/login");

  const full_name = String(formData.get("full_name") ?? "").trim();
  const email = String(formData.get("email") ?? "").trim() || null;
  const phone = String(formData.get("phone") ?? "").trim() || null;
  const department = String(formData.get("department") ?? "").trim() || null;
  const employee_code = String(formData.get("employee_code") ?? "").trim() || null;
  const photos = formData
    .getAll("photos")
    .filter((p): p is File => p instanceof File && p.size > 0);

  if (!full_name) {
    redirect(`/employees/new?error=${encodeURIComponent("Full name is required")}`);
  }
  if (photos.length < 1) {
    redirect(`/employees/new?error=${encodeURIComponent("Capture at least one photo")}`);
  }

  const { data: employee, error: insertError } = await supabase
    .from("employees")
    .insert({ full_name, email, phone, department, employee_code, created_by: user.id })
    .select("id")
    .single();

  if (insertError || !employee) {
    redirect(
      `/employees/new?error=${encodeURIComponent(insertError?.message ?? "Could not create employee")}`,
    );
  }

  for (const photo of photos) {
    const path = `${employee.id}/${randomUUID()}.jpg`;
    const { error: uploadError } = await supabase.storage
      .from("employee-photos")
      .upload(path, photo, { contentType: photo.type || "image/jpeg" });

    // Best-effort: the employee row still gets created even if one photo
    // upload fails -- an admin can revisit the employee page and re-enroll.
    if (uploadError) continue;

    await supabase
      .from("employee_photos")
      .insert({ employee_id: employee.id, storage_path: path });
  }

  revalidatePath("/employees");
  redirect(`/employees/${employee.id}`);
}

export async function updateEmployee(employeeId: string, formData: FormData) {
  const supabase = createClient();

  const full_name = String(formData.get("full_name") ?? "").trim();
  const email = String(formData.get("email") ?? "").trim() || null;
  const phone = String(formData.get("phone") ?? "").trim() || null;
  const department = String(formData.get("department") ?? "").trim() || null;
  const employee_code = String(formData.get("employee_code") ?? "").trim() || null;

  if (!full_name) {
    redirect(`/employees/${employeeId}/edit?error=${encodeURIComponent("Full name is required")}`);
  }

  const { error } = await supabase
    .from("employees")
    .update({ full_name, email, phone, department, employee_code })
    .eq("id", employeeId);

  if (error) {
    redirect(`/employees/${employeeId}/edit?error=${encodeURIComponent(error.message)}`);
  }

  revalidatePath(`/employees/${employeeId}`);
  revalidatePath("/employees");
  redirect(`/employees/${employeeId}`);
}

export async function deleteEmployee(employeeId: string) {
  const supabase = createClient();

  const { data: photos } = await supabase
    .from("employee_photos")
    .select("storage_path")
    .eq("employee_id", employeeId);

  if (photos && photos.length > 0) {
    // Best-effort: an orphaned storage object is harmless (private bucket),
    // so a failed removal here shouldn't block deleting the employee row.
    await supabase.storage
      .from("employee-photos")
      .remove(photos.map((p) => p.storage_path));
  }

  // Cascades to employee_photos and face_embeddings via their FK
  // `on delete cascade` (0001_schema.sql).
  await supabase.from("employees").delete().eq("id", employeeId);

  revalidatePath("/employees");
  redirect("/employees");
}

export async function toggleActive(employeeId: string, nextActive: boolean) {
  const supabase = createClient();
  await supabase.from("employees").update({ is_active: nextActive }).eq("id", employeeId);
  revalidatePath(`/employees/${employeeId}`);
  revalidatePath("/employees");
}

export async function resetEmbeddings(employeeId: string) {
  const supabase = createClient();
  await supabase.from("face_embeddings").delete().eq("employee_id", employeeId);
  await supabase.from("employees").update({ embedding_status: "pending" }).eq("id", employeeId);
  revalidatePath(`/employees/${employeeId}`);
}
