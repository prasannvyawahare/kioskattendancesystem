import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { ExportRegisterCsvButton } from "./export-register-csv-button";
import { MonthCalendar, type CalendarCell } from "@/components/MonthCalendar";
import { StudentFilterFields } from "@/components/StudentFilterFields";
import { pad, todayIso } from "@/lib/date-utils";
import { isNonWorkingDay } from "@/lib/attendance-status";
import {
  applyStudentFilters,
  distinctValues,
  filterQueryString,
  parseCombinedFilter,
} from "@/lib/student-filters";

export default async function AttendanceRegisterPage({
  searchParams,
}: {
  searchParams: { month?: string; filter?: string };
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

  const filters = parseCombinedFilter(searchParams.filter);
  const filterQuery = filterQueryString(filters);

  const { data: allActive } = await supabase
    .from("employees")
    .select("department, standard, section")
    .eq("is_active", true);
  const departments = distinctValues(allActive, "department");
  const standards = distinctValues(allActive, "standard");
  const sections = distinctValues(allActive, "section");

  const studentsQuery = applyStudentFilters(
    supabase
      .from("employees")
      .select("id, full_name, department, standard, section")
      .eq("is_active", true)
      .order("full_name"),
    filters,
  );
  const { data: students } = await studentsQuery;

  // Counts either event type as presence for the day: a kiosk running in
  // check_out_only mode (see supabase/migrations/0013_offline_sync.sql)
  // never writes a check_in row, so requiring check_in alone would mark
  // everyone scanned there as absent.
  const { data: logs } = await supabase
    .from("attendance_logs")
    .select("employee_id, event_date")
    .in("event_type", ["check_in", "check_out"])
    .gte("event_date", monthStart)
    .lte("event_date", monthEnd);

  const { data: holidayRows } = await supabase
    .from("holidays")
    .select("holiday_date, name")
    .gte("holiday_date", monthStart)
    .lte("holiday_date", monthEnd);
  const holidaySet = new Set((holidayRows ?? []).map((h) => h.holiday_date));
  const holidayNameByDate = new Map((holidayRows ?? []).map((h) => [h.holiday_date, h.name]));

  const presenceByStudent = new Map<string, Set<number>>();
  for (const log of logs ?? []) {
    const day = Number(log.event_date.slice(8, 10));
    if (!presenceByStudent.has(log.employee_id)) presenceByStudent.set(log.employee_id, new Set());
    presenceByStudent.get(log.employee_id)!.add(day);
  }

  const dayNumbers = Array.from({ length: daysInMonth }, (_, i) => i + 1);
  // Sundays and admin-added holidays (supabase/migrations/0024_holidays.sql)
  // don't count toward the working-day denominator -- they're marked NA
  // rather than counted as an absence.
  const workingDayNumbers = dayNumbers.filter((d) => !isNonWorkingDay(year, month, d, holidaySet));
  const workingElapsedDays = workingDayNumbers.filter((d) => d <= elapsedDays).length;
  const rows = (students ?? []).map((student) => {
    const presentDays = presenceByStudent.get(student.id) ?? new Set<number>();
    const presentCount = workingDayNumbers.filter((d) => d <= elapsedDays && presentDays.has(d)).length;
    const pct = workingElapsedDays > 0 ? Math.round((presentCount / workingElapsedDays) * 100) : null;
    return { student, presentDays, presentCount, pct };
  });

  const monthLabel = new Date(year, month - 1, 1).toLocaleDateString(undefined, {
    month: "long",
    year: "numeric",
  });

  // Aggregate daily presence across the (department-filtered) roster
  // already computed in `rows`, for the month-at-a-glance calendar.
  const today = todayIso();
  const calCells: CalendarCell[] = dayNumbers.map((d) => {
    const dateStr = `${monthValue}-${pad(d)}`;
    if (isNonWorkingDay(year, month, d, holidaySet)) {
      return {
        day: d,
        tone: "na",
        label: holidayNameByDate.get(dateStr) ?? "NA",
        isToday: dateStr === today,
      };
    }
    if (d > elapsedDays || rows.length === 0) {
      return { day: d, tone: "empty", isToday: dateStr === today };
    }
    const presentCount = rows.filter((r) => r.presentDays.has(d)).length;
    const pct = Math.round((presentCount / rows.length) * 100);
    const tone: CalendarCell["tone"] = pct >= 90 ? "high" : pct >= 70 ? "mid" : "low";
    return {
      day: d,
      href: `/attendance?date=${dateStr}`,
      label: `${presentCount}/${rows.length}`,
      tone,
      isToday: dateStr === today,
    };
  });

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between print:hidden">
        <div>
          <h1 className="text-lg font-semibold text-slate-900">Monthly register</h1>
          <p className="text-sm text-slate-500">{monthLabel}</p>
        </div>
        <div className="flex items-center gap-4">
          <ExportRegisterCsvButton
            monthLabel={monthLabel}
            days={dayNumbers}
            nonWorkingDays={dayNumbers.filter((d) => isNonWorkingDay(year, month, d, holidaySet))}
            rows={rows.map((r) => ({
              full_name: r.student.full_name,
              presentDays: Array.from(r.presentDays),
              pct: r.pct,
            }))}
          />
          <Link href="/attendance" className="text-sm text-slate-500 hover:text-slate-900">
            Back to log
          </Link>
        </div>
      </div>

      {/* Calendar sits above the register, not beside it -- the table itself
          runs to 31 day-columns and needs the full content width, so a
          fixed-width sidebar here would just squeeze it into scrolling
          sooner than necessary. */}
      <details className="group rounded-xl border border-slate-200 bg-white p-4 text-sm print:hidden">
        <summary className="flex cursor-pointer list-none items-center justify-between font-medium text-slate-900">
          <span>Month at a glance</span>
          <span className="text-xs font-normal text-slate-400 group-open:hidden">Show calendar</span>
          <span className="hidden text-xs font-normal text-slate-400 group-open:inline">Hide calendar</span>
        </summary>
        <div className="mt-3 max-w-sm space-y-2">
          <MonthCalendar
            year={year}
            month={month}
            cells={calCells}
            title={monthLabel}
            prevHref={`/attendance/register?month=${prevMonthValue}${filterQuery ? `&${filterQuery}` : ""}`}
            nextHref={`/attendance/register?month=${nextMonthValue}${filterQuery ? `&${filterQuery}` : ""}`}
          />
          <p className="px-1 text-xs text-slate-400">Click a day to see its raw attendance log.</p>
        </div>
      </details>

      <div className="space-y-6">
        <form className="flex flex-wrap items-end gap-3 rounded-xl border border-slate-200 bg-white p-4 text-sm print:hidden">
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
            filters={filters}
          />
          <button
            type="submit"
            className="rounded-md bg-indigo-600 px-3 py-1.5 font-medium text-white hover:bg-indigo-500"
          >
            Filter
          </button>
        </form>

        <div className="overflow-x-auto rounded-xl border border-slate-200 bg-white">
          <table className="w-full text-xs print:text-[10px]">
            <thead className="border-b border-slate-200 bg-slate-50 text-left text-slate-500">
              <tr>
                <th className="sticky left-0 z-10 bg-slate-50 px-3 py-2 font-medium">Student</th>
                {dayNumbers.map((d) => (
                  <th key={d} className="px-1.5 py-2 text-center font-medium">
                    {d}
                  </th>
                ))}
                <th className="px-3 py-2 text-center font-medium">%</th>
              </tr>
            </thead>
            <tbody>
              {rows.map(({ student, presentDays, pct }) => (
                <tr key={student.id} className="border-b border-slate-100 last:border-0">
                  <td className="sticky left-0 z-10 bg-white px-3 py-2 font-medium text-slate-900">
                    {student.full_name}
                  </td>
                  {dayNumbers.map((d) => (
                    <td key={d} className="px-1.5 py-2 text-center">
                      {isNonWorkingDay(year, month, d, holidaySet) ? (
                        <span className="inline-block rounded bg-slate-100 px-1.5 py-0.5 font-medium text-slate-500">
                          NA
                        </span>
                      ) : d > elapsedDays ? (
                        <span className="text-slate-300">-</span>
                      ) : presentDays.has(d) ? (
                        <span className="inline-block rounded bg-emerald-50 px-1.5 py-0.5 font-medium text-emerald-700">
                          P
                        </span>
                      ) : (
                        <span className="inline-block rounded bg-red-50 px-1.5 py-0.5 font-medium text-red-700">
                          A
                        </span>
                      )}
                    </td>
                  ))}
                  <td className="px-3 py-2 text-center font-medium text-slate-900">
                    {pct == null ? "-" : `${pct}%`}
                  </td>
                </tr>
              ))}
              {rows.length === 0 && (
                <tr>
                  <td colSpan={dayNumbers.length + 2} className="px-4 py-8 text-center text-slate-400">
                    No active students match this filter.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
