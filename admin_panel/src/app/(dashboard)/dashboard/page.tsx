import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { LiveAttendanceFeed } from "./live-attendance-feed";
import { AutoRefresh } from "@/components/AutoRefresh";

export default async function DashboardPage() {
  const supabase = createClient();
  const today = new Date().toISOString().slice(0, 10);

  // Independent queries -- run concurrently rather than paying two
  // sequential Supabase round-trips back to back.
  const [{ data: todayLogs }, { data: activeEmployees }] = await Promise.all([
    supabase
      .from("attendance_logs")
      .select("id, employee_id, event_type, scanned_at")
      .eq("event_date", today)
      .order("scanned_at", { ascending: false }),
    // Full active roster (not just today's scanners) -- needed to figure out
    // who *hasn't* shown up yet and to break attendance down by department.
    supabase
      .from("employees")
      .select("id, full_name, department")
      .eq("is_active", true)
      .order("full_name"),
  ]);

  const nameById = new Map((activeEmployees ?? []).map((e) => [e.id, e.full_name]));
  const logsWithNames = (todayLogs ?? []).map((log) => ({
    ...log,
    employee_name: nameById.get(log.employee_id) ?? "Unknown",
  }));

  const checkIns = todayLogs?.filter((l) => l.event_type === "check_in").length ?? 0;
  const checkOuts = todayLogs?.filter((l) => l.event_type === "check_out").length ?? 0;

  const presentIds = new Set(
    (todayLogs ?? []).filter((l) => l.event_type === "check_in").map((l) => l.employee_id),
  );
  const roster = activeEmployees ?? [];
  const absentStudents = roster.filter((e) => !presentIds.has(e.id));

  const departmentStats = new Map<string, { active: number; present: number }>();
  for (const e of roster) {
    const dept = e.department?.trim() || "Unassigned";
    const entry = departmentStats.get(dept) ?? { active: 0, present: 0 };
    entry.active += 1;
    if (presentIds.has(e.id)) entry.present += 1;
    departmentStats.set(dept, entry);
  }
  const departmentRows = Array.from(departmentStats.entries()).sort((a, b) =>
    a[0].localeCompare(b[0]),
  );

  return (
    <div className="space-y-8">
      <AutoRefresh />
      <div>
        <h1 className="text-lg font-semibold text-slate-900">Dashboard</h1>
        <p className="text-sm text-slate-500">Today, {new Date().toLocaleDateString()}</p>
      </div>

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
        <StatCard label="Active students" value={roster.length} accent="indigo" />
        <StatCard label="Check-ins today" value={checkIns} accent="emerald" />
        <StatCard label="Check-outs today" value={checkOuts} accent="amber" />
      </div>

      <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
        <section className="rounded-xl border border-slate-200 bg-white">
          <div className="border-b border-slate-200 px-4 py-3">
            <h2 className="text-sm font-medium text-slate-900">
              Absent today ({absentStudents.length})
            </h2>
          </div>
          <ul className="max-h-80 divide-y divide-slate-100 overflow-y-auto text-sm">
            {absentStudents.map((student) => (
              <li key={student.id} className="flex items-center justify-between px-4 py-2.5">
                <Link
                  href={`/employees/${student.id}`}
                  className="font-medium text-slate-900 hover:underline"
                >
                  {student.full_name}
                </Link>
                <span className="text-slate-500">{student.department ?? "-"}</span>
              </li>
            ))}
            {absentStudents.length === 0 && (
              <li className="px-4 py-8 text-center text-slate-400">
                Everyone active has checked in today.
              </li>
            )}
          </ul>
        </section>

        <section className="rounded-xl border border-slate-200 bg-white">
          <div className="border-b border-slate-200 px-4 py-3">
            <h2 className="text-sm font-medium text-slate-900">By department</h2>
          </div>
          <table className="w-full text-sm">
            <thead className="text-left text-slate-500">
              <tr>
                <th className="px-4 py-2 font-medium">Department</th>
                <th className="px-4 py-2 font-medium">Active</th>
                <th className="px-4 py-2 font-medium">Present</th>
                <th className="px-4 py-2 font-medium">%</th>
              </tr>
            </thead>
            <tbody>
              {departmentRows.map(([dept, stats]) => (
                <tr key={dept} className="border-t border-slate-100">
                  <td className="px-4 py-2 text-slate-900">{dept}</td>
                  <td className="px-4 py-2 text-slate-600">{stats.active}</td>
                  <td className="px-4 py-2 text-slate-600">{stats.present}</td>
                  <td className="px-4 py-2 text-slate-600">
                    {stats.active > 0 ? Math.round((stats.present / stats.active) * 100) : 0}%
                  </td>
                </tr>
              ))}
              {departmentRows.length === 0 && (
                <tr>
                  <td colSpan={4} className="px-4 py-8 text-center text-slate-400">
                    No active students yet.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </section>
      </div>

      <LiveAttendanceFeed initialLogs={logsWithNames} today={today} />
    </div>
  );
}

const ACCENT_BORDERS = {
  indigo: "border-l-indigo-500",
  emerald: "border-l-emerald-500",
  amber: "border-l-amber-500",
} as const;

function StatCard({
  label,
  value,
  accent,
}: {
  label: string;
  value: number;
  accent: keyof typeof ACCENT_BORDERS;
}) {
  return (
    <div
      className={`rounded-xl border border-l-4 border-slate-200 bg-white p-5 ${ACCENT_BORDERS[accent]}`}
    >
      <p className="text-sm text-slate-500">{label}</p>
      <p className="mt-2 text-2xl font-semibold text-slate-900">{value}</p>
    </div>
  );
}
