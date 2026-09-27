import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { GenerateReportPdfButton } from "./generate-report-pdf-button";
import { StudentFilterFields } from "@/components/StudentFilterFields";
import { pad } from "@/lib/date-utils";
import { isNonWorkingDay } from "@/lib/attendance-status";
import { applyStudentFilters, distinctValues, filterQueryString } from "@/lib/student-filters";

export default async function ReportsPage({
  searchParams,
}: {
  searchParams: { month?: string; department?: string; standard?: string; section?: string };
}) {
  const supabase = createClient();
  const now = new Date();

  let year = now.getFullYear();
  let month = now.getMonth() + 1; // 1-12
  if (searchParams.month && /^\d{4}-\d{2}$/.test(searchParams.month)) {
    const [y, m] = searchParams.month.split("-").map(Number);
    year = y;
    month = m;
  }
  const monthValue = `${year}-${pad(month)}`;
  const daysInMonth = new Date(year, month, 0).getDate();
  const isFutureMonth =
    year > now.getFullYear() || (year === now.getFullYear() && month > now.getMonth() + 1);
  const isCurrentMonth = year === now.getFullYear() && month === now.getMonth() + 1;
  const elapsedDays = isFutureMonth ? 0 : isCurrentMonth ? now.getDate() : daysInMonth;

  const monthStart = `${monthValue}-01`;
  const monthEnd = `${monthValue}-${pad(daysInMonth)}`;

  const prevDate = new Date(year, month - 2, 1);
  const nextDate = new Date(year, month, 1);
  const prevMonthValue = `${prevDate.getFullYear()}-${pad(prevDate.getMonth() + 1)}`;
  const nextMonthValue = `${nextDate.getFullYear()}-${pad(nextDate.getMonth() + 1)}`;
  const monthLabel = new Date(year, month - 1, 1).toLocaleDateString(undefined, {
    month: "long",
    year: "numeric",
  });

  const filters = {
    department: searchParams.department,
    standard: searchParams.standard,
    section: searchParams.section,
  };
  const filterQuery = filterQueryString(filters);

  const studentsQuery = applyStudentFilters(
    supabase
      .from("employees")
      .select("id, full_name, employee_code, department, standard, section")
      .eq("is_active", true)
      .order("full_name"),
    filters,
  );

  // Independent queries -- run concurrently rather than paying three
  // sequential Supabase round-trips back to back.
  const [{ data: allActive }, { data: students }, { data: logs }, { data: holidayRows }] = await Promise.all([
    supabase.from("employees").select("department, standard, section").eq("is_active", true),
    studentsQuery,
    // Counts either event type as presence for the day: a kiosk running in
    // check_out_only mode (see supabase/migrations/0013_offline_sync.sql)
    // never writes a check_in row, so requiring check_in alone would mark
    // everyone scanned there as absent.
    supabase
      .from("attendance_logs")
      .select("employee_id, event_date")
      .in("event_type", ["check_in", "check_out"])
      .gte("event_date", monthStart)
      .lte("event_date", monthEnd),
    supabase
      .from("holidays")
      .select("holiday_date")
      .gte("holiday_date", monthStart)
      .lte("holiday_date", monthEnd),
  ]);
  const departments = distinctValues(allActive, "department");
  const standards = distinctValues(allActive, "standard");
  const sections = distinctValues(allActive, "section");

  const presenceByStudent = new Map<string, Set<number>>();
  for (const log of logs ?? []) {
    const day = Number(log.event_date.slice(8, 10));
    if (!presenceByStudent.has(log.employee_id)) presenceByStudent.set(log.employee_id, new Set());
    presenceByStudent.get(log.employee_id)!.add(day);
  }

  const holidaySet = new Set((holidayRows ?? []).map((h) => h.holiday_date));
  const dayNumbers = Array.from({ length: daysInMonth }, (_, i) => i + 1);
  // Sundays and admin-added holidays don't count toward the working-day
  // denominator -- see supabase/migrations/0024_holidays.sql.
  const workingDayNumbers = dayNumbers.filter((d) => !isNonWorkingDay(year, month, d, holidaySet));
  const workingElapsedDays = workingDayNumbers.filter((d) => d <= elapsedDays).length;

  const groupsByDepartment = new Map<
    string,
    { full_name: string; employee_code: string | null; presentCount: number; pct: number | null }[]
  >();
  for (const student of students ?? []) {
    const dept = student.department?.trim() || "Unassigned";
    const presentDays = presenceByStudent.get(student.id) ?? new Set<number>();
    const presentCount = workingDayNumbers.filter((d) => d <= elapsedDays && presentDays.has(d)).length;
    const pct = workingElapsedDays > 0 ? Math.round((presentCount / workingElapsedDays) * 100) : null;
    const row = { full_name: student.full_name, employee_code: student.employee_code, presentCount, pct };
    if (!groupsByDepartment.has(dept)) groupsByDepartment.set(dept, []);
    groupsByDepartment.get(dept)!.push(row);
  }

  const groups = Array.from(groupsByDepartment.entries())
    .sort((a, b) => a[0].localeCompare(b[0]))
    .map(([department, rows]) => {
      const withPct = rows.filter((r) => r.pct != null);
      const avgPct =
        withPct.length > 0
          ? Math.round(withPct.reduce((sum, r) => sum + (r.pct ?? 0), 0) / withPct.length)
          : null;
      return { department, activeCount: rows.length, avgPct, students: rows };
    });

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-lg font-semibold text-slate-900">Reports</h1>
          <p className="text-sm text-slate-500">Department-wise attendance for {monthLabel}</p>
        </div>
        <GenerateReportPdfButton monthLabel={monthLabel} groups={groups} />
      </div>

      <form className="flex flex-wrap items-end gap-3 rounded-xl border border-slate-200 bg-white p-4 text-sm">
        <div className="space-y-1">
          <label htmlFor="month" className="block text-xs font-medium text-slate-600">
            Month
          </label>
          <input
            id="month"
            name="month"
            type="month"
            defaultValue={monthValue}
            className="rounded-md border border-slate-300 px-2 py-1.5"
          />
        </div>
        <StudentFilterFields
          departments={departments}
          standards={standards}
          sections={sections}
          department={searchParams.department}
          standard={searchParams.standard}
          section={searchParams.section}
        />
        <button
          type="submit"
          className="rounded-md bg-indigo-600 px-3 py-1.5 font-medium text-white hover:bg-indigo-500"
        >
          Filter
        </button>
        <div className="ml-auto flex items-center gap-2 text-xs text-slate-500">
          <Link
            href={`/reports?month=${prevMonthValue}${filterQuery ? `&${filterQuery}` : ""}`}
            className="rounded px-2 py-1 hover:bg-slate-100 hover:text-slate-900"
          >
            ← Previous month
          </Link>
          <Link
            href={`/reports?month=${nextMonthValue}${filterQuery ? `&${filterQuery}` : ""}`}
            className="rounded px-2 py-1 hover:bg-slate-100 hover:text-slate-900"
          >
            Next month →
          </Link>
        </div>
      </form>

      <div className="space-y-6">
        {groups.map((group) => (
          <section key={group.department} className="overflow-hidden rounded-xl border border-slate-200 bg-white">
            <div className="flex items-center justify-between border-b border-slate-200 px-4 py-3">
              <h2 className="text-sm font-medium text-slate-900">{group.department}</h2>
              <p className="text-xs text-slate-500">
                {group.activeCount} student{group.activeCount === 1 ? "" : "s"} · avg{" "}
                {group.avgPct == null ? "-" : `${group.avgPct}%`} present
              </p>
            </div>
            <table className="w-full text-sm">
              <thead className="text-left text-slate-500">
                <tr>
                  <th className="px-4 py-2 font-medium">Student</th>
                  <th className="px-4 py-2 font-medium">Code</th>
                  <th className="px-4 py-2 font-medium">Present days</th>
                  <th className="px-4 py-2 font-medium">%</th>
                </tr>
              </thead>
              <tbody>
                {group.students.map((student) => (
                  <tr key={student.full_name} className="border-t border-slate-100">
                    <td className="px-4 py-2 text-slate-900">{student.full_name}</td>
                    <td className="px-4 py-2 text-slate-600">{student.employee_code ?? "-"}</td>
                    <td className="px-4 py-2 text-slate-600">{student.presentCount}</td>
                    <td className="px-4 py-2 text-slate-600">
                      {student.pct == null ? "-" : `${student.pct}%`}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </section>
        ))}
        {groups.length === 0 && (
          <div className="rounded-xl border border-slate-200 bg-white px-4 py-8 text-center text-slate-400">
            No active students yet.
          </div>
        )}
      </div>
    </div>
  );
}
