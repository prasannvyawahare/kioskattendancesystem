import Link from "next/link";
import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { updateEmployee } from "../../actions";

export default async function EditEmployeePage({
  params,
  searchParams,
}: {
  params: { id: string };
  searchParams: { error?: string };
}) {
  const supabase = createClient();

  const { data: employee } = await supabase
    .from("employees")
    .select("*")
    .eq("id", params.id)
    .single();

  if (!employee) notFound();

  return (
    <div className="max-w-2xl space-y-6">
      <div className="flex items-center justify-between">
        <h1 className="text-lg font-semibold text-slate-900">Edit student</h1>
        <Link href={`/employees/${employee.id}`} className="text-sm text-slate-500 hover:text-slate-900">
          Cancel
        </Link>
      </div>

      {searchParams.error && (
        <p className="rounded-md bg-red-50 px-3 py-2 text-sm text-red-700">{searchParams.error}</p>
      )}

      <form action={updateEmployee.bind(null, employee.id)} className="space-y-6">
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <Field label="Full name" name="full_name" defaultValue={employee.full_name} required />
          <Field label="Student code" name="employee_code" defaultValue={employee.employee_code} />
          <Field label="Email" name="email" type="email" defaultValue={employee.email} />
          <Field label="Phone" name="phone" defaultValue={employee.phone} />
          <Field label="Department" name="department" defaultValue={employee.department} />
        </div>

        <div className="space-y-4 rounded-xl border border-slate-200 p-4">
          <div>
            <h2 className="text-sm font-medium text-slate-900">Parent / guardian details</h2>
            <p className="text-xs text-slate-500">
              Used to contact a parent about their child&apos;s attendance.
            </p>
          </div>
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <div className="space-y-4">
              <p className="text-xs font-semibold uppercase tracking-wide text-slate-500">
                Mother
              </p>
              <Field label="Name" name="mother_name" defaultValue={employee.mother_name} />
              <Field label="Phone" name="mother_phone" defaultValue={employee.mother_phone} />
              <Field
                label="Email"
                name="mother_email"
                type="email"
                defaultValue={employee.mother_email}
              />
            </div>
            <div className="space-y-4">
              <p className="text-xs font-semibold uppercase tracking-wide text-slate-500">
                Father
              </p>
              <Field label="Name" name="father_name" defaultValue={employee.father_name} />
              <Field label="Phone" name="father_phone" defaultValue={employee.father_phone} />
              <Field
                label="Email"
                name="father_email"
                type="email"
                defaultValue={employee.father_email}
              />
            </div>
          </div>
        </div>

        <button
          type="submit"
          className="rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-500"
        >
          Save changes
        </button>
      </form>
    </div>
  );
}

function Field({
  label,
  name,
  type = "text",
  defaultValue,
  required,
}: {
  label: string;
  name: string;
  type?: string;
  defaultValue?: string | null;
  required?: boolean;
}) {
  return (
    <div className="space-y-1">
      <label htmlFor={name} className="text-sm font-medium text-slate-700">
        {label}
      </label>
      <input
        id={name}
        name={name}
        type={type}
        defaultValue={defaultValue ?? ""}
        required={required}
        className="w-full rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-slate-500"
      />
    </div>
  );
}
