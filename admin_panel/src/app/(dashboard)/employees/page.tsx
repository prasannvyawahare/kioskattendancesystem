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

const PAGE_SIZE = 50;

export default async function EmployeesPage({
  searchParams,
}: {
  searchParams: { page?: string };
}) {
  const supabase = createClient();
  const page = Math.max(1, Number(searchParams.page) || 1);
  const from = (page - 1) * PAGE_SIZE;
  const to = from + PAGE_SIZE - 1;

  const {
    data: employees,
    count,
  } = await supabase
    .from("employees")
    .select("id, full_name, employee_code, department, is_active, embedding_status", {
      count: "exact",
    })
    .order("created_at", { ascending: false })
    .range(from, to);

  const totalPages = Math.max(1, Math.ceil((count ?? 0) / PAGE_SIZE));

  return (
    <div>
      <AutoRefresh />
      <div className="flex items-center justify-between">
        <h1 className="text-lg font-semibold text-slate-900">Students</h1>
        <Link
          href="/employees/new"
          className="rounded-md bg-indigo-600 px-3 py-2 text-sm font-medium text-white hover:bg-indigo-500"
        >
          Register student
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
                  No students registered yet.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      {totalPages > 1 && (
        <div className="mt-4 flex items-center justify-between text-sm text-slate-600">
          <Link
            href={`/employees?page=${page - 1}`}
            aria-disabled={page <= 1}
            className={`rounded-md border border-slate-300 px-3 py-1.5 ${
              page <= 1 ? "pointer-events-none opacity-40" : "hover:bg-slate-50"
            }`}
          >
            ← Previous
          </Link>
          <span>
            Page {page} of {totalPages}
          </span>
          <Link
            href={`/employees?page=${page + 1}`}
            aria-disabled={page >= totalPages}
            className={`rounded-md border border-slate-300 px-3 py-1.5 ${
              page >= totalPages ? "pointer-events-none opacity-40" : "hover:bg-slate-50"
            }`}
          >
            Next →
          </Link>
        </div>
      )}
    </div>
  );
}
