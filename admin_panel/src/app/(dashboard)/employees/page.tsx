import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import type { EmbeddingStatus } from "@/lib/database.types";
import { AutoRefresh } from "@/components/AutoRefresh";

const STATUS_STYLES: Record<EmbeddingStatus, string> = {
  pending: "bg-amber-50 text-amber-700",
  processing: "bg-blue-50 text-blue-700",
  completed: "bg-emerald-50 text-emerald-700",
  failed: "bg-red-50 text-red-700",
};

export default async function EmployeesPage() {
  const supabase = createClient();
  const { data: employees } = await supabase
    .from("employees")
    .select("id, full_name, employee_code, department, is_active, embedding_status")
    .order("created_at", { ascending: false });

  return (
    <div>
      <AutoRefresh />
      <div className="flex items-center justify-between">
        <h1 className="text-lg font-semibold text-slate-900">Employees</h1>
        <Link
          href="/employees/new"
          className="rounded-md bg-slate-900 px-3 py-2 text-sm font-medium text-white hover:bg-slate-800"
        >
          Register employee
        </Link>
      </div>

      <div className="mt-6 overflow-hidden rounded-xl border border-slate-200 bg-white">
        <table className="w-full text-sm">
          <thead className="border-b border-slate-200 bg-slate-50 text-left text-slate-500">
            <tr>
              <th className="px-4 py-3 font-medium">Name</th>
              <th className="px-4 py-3 font-medium">Code</th>
              <th className="px-4 py-3 font-medium">Department</th>
              <th className="px-4 py-3 font-medium">Recognition status</th>
              <th className="px-4 py-3 font-medium">Active</th>
            </tr>
          </thead>
          <tbody>
            {employees?.map((employee) => (
              <tr key={employee.id} className="border-b border-slate-100 last:border-0">
                <td className="px-4 py-3">
                  <Link
                    href={`/employees/${employee.id}`}
                    className="font-medium text-slate-900 hover:underline"
                  >
                    {employee.full_name}
                  </Link>
                </td>
                <td className="px-4 py-3 text-slate-600">{employee.employee_code ?? "-"}</td>
                <td className="px-4 py-3 text-slate-600">{employee.department ?? "-"}</td>
                <td className="px-4 py-3">
                  <span
                    className={`rounded-full px-2 py-1 text-xs font-medium ${STATUS_STYLES[employee.embedding_status]}`}
                  >
                    {employee.embedding_status}
                  </span>
                </td>
                <td className="px-4 py-3 text-slate-600">{employee.is_active ? "Yes" : "No"}</td>
              </tr>
            ))}
            {employees?.length === 0 && (
              <tr>
                <td colSpan={5} className="px-4 py-8 text-center text-slate-400">
                  No employees registered yet.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
