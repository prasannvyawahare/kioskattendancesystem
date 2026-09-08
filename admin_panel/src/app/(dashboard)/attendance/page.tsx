import { createClient } from "@/lib/supabase/server";
import { ExportCsvButton } from "./export-csv-button";

export default async function AttendancePage({
  searchParams,
}: {
  searchParams: { date?: string; employee_id?: string };
}) {
  const supabase = createClient();

  const { data: employees } = await supabase
    .from("employees")
    .select("id, full_name")
    .order("full_name");

  let query = supabase
    .from("attendance_logs")
    .select("id, employee_id, event_type, event_date, scanned_at, confidence")
    .order("scanned_at", { ascending: false })
    .limit(200);

  if (searchParams.date) query = query.eq("event_date", searchParams.date);
  if (searchParams.employee_id) query = query.eq("employee_id", searchParams.employee_id);

  const { data: logs } = await query;

  const nameById = new Map((employees ?? []).map((e) => [e.id, e.full_name]));
  const rows = (logs ?? []).map((log) => ({
    ...log,
    employee_name: nameById.get(log.employee_id) ?? "Unknown",
  }));

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <h1 className="text-lg font-semibold text-slate-900">Attendance log</h1>
        <ExportCsvButton rows={rows} />
      </div>

      <form className="flex flex-wrap gap-3 rounded-xl border border-slate-200 bg-white p-4 text-sm">
        <div className="space-y-1">
          <label htmlFor="date" className="block text-xs font-medium text-slate-600">
            Date
          </label>
          <input
            id="date"
            name="date"
            type="date"
            defaultValue={searchParams.date}
            className="rounded-md border border-slate-300 px-2 py-1.5"
          />
        </div>
        <div className="space-y-1">
          <label htmlFor="employee_id" className="block text-xs font-medium text-slate-600">
            Employee
          </label>
          <select
            id="employee_id"
            name="employee_id"
            defaultValue={searchParams.employee_id ?? ""}
            className="rounded-md border border-slate-300 px-2 py-1.5"
          >
            <option value="">All employees</option>
            {employees?.map((e) => (
              <option key={e.id} value={e.id}>
                {e.full_name}
              </option>
            ))}
          </select>
        </div>
        <button
          type="submit"
          className="self-end rounded-md bg-slate-900 px-3 py-1.5 font-medium text-white"
        >
          Filter
        </button>
      </form>

      <div className="overflow-hidden rounded-xl border border-slate-200 bg-white">
        <table className="w-full text-sm">
          <thead className="border-b border-slate-200 bg-slate-50 text-left text-slate-500">
            <tr>
              <th className="px-4 py-3 font-medium">Employee</th>
              <th className="px-4 py-3 font-medium">Event</th>
              <th className="px-4 py-3 font-medium">Date</th>
              <th className="px-4 py-3 font-medium">Time</th>
              <th className="px-4 py-3 font-medium">Confidence</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((row) => (
              <tr key={row.id} className="border-b border-slate-100 last:border-0">
                <td className="px-4 py-3 font-medium text-slate-900">{row.employee_name}</td>
                <td className="px-4 py-3 capitalize text-slate-600">
                  {row.event_type.replace("_", " ")}
                </td>
                <td className="px-4 py-3 text-slate-600">{row.event_date}</td>
                <td className="px-4 py-3 text-slate-600">
                  {new Date(row.scanned_at).toLocaleTimeString()}
                </td>
                <td className="px-4 py-3 text-slate-600">
                  {row.confidence != null ? row.confidence.toFixed(2) : "-"}
                </td>
              </tr>
            ))}
            {rows.length === 0 && (
              <tr>
                <td colSpan={5} className="px-4 py-8 text-center text-slate-400">
                  No attendance records match this filter.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
