"use server";

import { randomUUID } from "crypto";
import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import type { Gender } from "@/lib/database.types";

function parseGender(formData: FormData): Gender | null {
  const value = String(formData.get("gender") ?? "");
  return value === "male" || value === "female" || value === "other" ? value : null;
}

// Mirrors MIN_PHOTOS in register-employee-form.tsx -- the client already
// disables submit below this count, but the server action is the actual
// enforcement point since a form can be submitted by other means.
const MIN_PHOTOS = 3;

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
  const standard = String(formData.get("standard") ?? "").trim() || null;
  const section = String(formData.get("section") ?? "").trim() || null;
  const gender = parseGender(formData);
  const mother_name = String(formData.get("mother_name") ?? "").trim() || null;
  const mother_phone = String(formData.get("mother_phone") ?? "").trim() || null;
  const mother_email = String(formData.get("mother_email") ?? "").trim() || null;
  const father_name = String(formData.get("father_name") ?? "").trim() || null;
  const father_phone = String(formData.get("father_phone") ?? "").trim() || null;
  const father_email = String(formData.get("father_email") ?? "").trim() || null;
  const photos = formData
    .getAll("photos")
    .filter((p): p is File => p instanceof File && p.size > 0);

  if (!full_name) {
    redirect(`/employees/new?error=${encodeURIComponent("Full name is required")}`);
  }
  if (photos.length < MIN_PHOTOS) {
    redirect(
      `/employees/new?error=${encodeURIComponent(`Capture at least ${MIN_PHOTOS} photos`)}`,
    );
  }

  const { data: employee, error: insertError } = await supabase
    .from("employees")
    .insert({
      full_name,
      email,
      phone,
      department,
      employee_code,
      standard,
      section,
      gender,
      mother_name,
      mother_phone,
      mother_email,
      father_name,
      father_phone,
      father_email,
      created_by: user.id,
    })
    .select("id")
    .single();

  if (insertError || !employee) {
    redirect(
      `/employees/new?error=${encodeURIComponent(insertError?.message ?? "Could not create student")}`,
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
  const standard = String(formData.get("standard") ?? "").trim() || null;
  const section = String(formData.get("section") ?? "").trim() || null;
  const gender = parseGender(formData);
  const mother_name = String(formData.get("mother_name") ?? "").trim() || null;
  const mother_phone = String(formData.get("mother_phone") ?? "").trim() || null;
  const mother_email = String(formData.get("mother_email") ?? "").trim() || null;
  const father_name = String(formData.get("father_name") ?? "").trim() || null;
  const father_phone = String(formData.get("father_phone") ?? "").trim() || null;
  const father_email = String(formData.get("father_email") ?? "").trim() || null;

  if (!full_name) {
    redirect(`/employees/${employeeId}/edit?error=${encodeURIComponent("Full name is required")}`);
  }

  const { error } = await supabase
    .from("employees")
    .update({
      full_name,
      email,
      phone,
      department,
      employee_code,
      standard,
      section,
      gender,
      mother_name,
      mother_phone,
      mother_email,
      father_name,
      father_phone,
      father_email,
    })
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
  const { error } = await supabase
    .from("employees")
    .update({ is_active: nextActive })
    .eq("id", employeeId);

  if (error) {
    redirect(`/employees/${employeeId}?error=${encodeURIComponent(error.message)}`);
  }

  revalidatePath(`/employees/${employeeId}`);
  revalidatePath("/employees");
}

export async function resetEmbeddings(employeeId: string) {
  const supabase = createClient();

  const { error: deleteError } = await supabase
    .from("face_embeddings")
    .delete()
    .eq("employee_id", employeeId);
  if (deleteError) {
    redirect(`/employees/${employeeId}?error=${encodeURIComponent(deleteError.message)}`);
  }

  const { error: updateError } = await supabase
    .from("employees")
    .update({ embedding_status: "pending" })
    .eq("id", employeeId);
  if (updateError) {
    redirect(`/employees/${employeeId}?error=${encodeURIComponent(updateError.message)}`);
  }

  revalidatePath(`/employees/${employeeId}`);
}
