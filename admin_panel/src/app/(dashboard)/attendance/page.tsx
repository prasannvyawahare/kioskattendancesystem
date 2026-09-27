import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { ExportCsvButton } from "./export-csv-button";
import { DeleteLogButton } from "./DeleteLogButton";
import { AutoRefresh } from "@/components/AutoRefresh";
import { MonthCalendar, type CalendarCell } from "@/components/MonthCalendar";
import { StudentFilterFields } from "@/components/StudentFilterFields";
import { pad, todayIso, formatTime } from "@/lib/date-utils";
import { isNonWorkingDay, eventTypeLabel } from "@/lib/attendance-status";
import {
  applyStudentFilters,
  distinctValues,
  filterQueryString,
  parseCombinedFilter,
} from "@/lib/student-filters";

const PAGE_SIZE = 20;
// CSV export isn't paginated -- it grabs up to this many of the most recent
// filtered rows regardless of which page the table is showing.
const EXPORT_LIMIT = 200;

export default async function AttendancePage({
  searchParams,
}: {
  searchParams: {
    date?: string;
    employee_id?: string;
    cal?: string;
    error?: string;
    filter?: string;
    page?: string;
  };
}) {
  const supabase = createClient();
  const page = Math.max(1, Number(searchParams.page) || 1);
  const from = (page - 1) * PAGE_SIZE;
  const to = from + PAGE_SIZE - 1;

  // Calendar month defaults to the active date filter's month, else the
  // current month; navigated independently via ?cal= so browsing months
  // doesn't disturb the table's own date filter until a day is clicked.
  const now = new Date();
  let calYear = now.getFullYear();
  let calMonth = now.getMonth() + 1;
  if (searchParams.cal && /^\d{4}-\d{2}$/.test(searchParams.cal)) {
    const [y, m] = searchParams.cal.split("-").map(Number);
    calYear = y;
    calMonth = m;
  } else if (searchParams.date && /^\d{4}-\d{2}-\d{2}$/.test(searchParams.date)) {
    const [y, m] = searchParams.date.split("-").map(Number);
    calYear = y;
    calMonth = m;
  }
  const calMonthValue = `${calYear}-${pad(calMonth)}`;
  const calDaysInMonth = new Date(calYear, calMonth, 0).getDate();
  const calMonthStart = `${calMonthValue}-01`;
  const calMonthEnd = `${calMonthValue}-${pad(calDaysInMonth)}`;

  const prevCal = new Date(calYear, calMonth - 2, 1);
  const nextCal = new Date(calYear, calMonth, 1);
  const prevCalValue = `${prevCal.getFullYear()}-${pad(prevCal.getMonth() + 1)}`;
  const nextCalValue = `${nextCal.getFullYear()}-${pad(nextCal.getMonth() + 1)}`;
  const calMonthLabel = new Date(calYear, calMonth - 1, 1).toLocaleDateString(undefined, {
    month: "long",
    year: "numeric",
  });

  const filters = parseCombinedFilter(searchParams.filter);
  const filterQuery = filterQueryString(filters);
  const hasStudentFilters = Boolean(filters.department || filters.standard || filters.section);

  // Resolved first (rather than folded into the Promise.all below) because
  // logsQuery/calLogs both need the id list before they can be built.
  const [{ data: allActive }, { data: filterMatches }] = await Promise.all([
    supabase.from("employees").select("department, standard, section").eq("is_active", true),
    hasStudentFilters
      ? applyStudentFilters(supabase.from("employees").select("id"), filters)
      : Promise.resolve({ data: null }),
  ]);
  const departments = distinctValues(allActive, "department");
  const standards = distinctValues(allActive, "standard");
  const sections = distinctValues(allActive, "section");
  const filteredEmployeeIds = hasStudentFilters ? (filterMatches ?? []).map((e) => e.id) : null;

  function buildLogsQuery() {
    let q = supabase
      .from("attendance_logs")
      .select("id, employee_id, event_type, event_date, scanned_at, confidence", {
        count: "exact",
      })
      .order("scanned_at", { ascending: false });
    if (searchParams.date) q = q.eq("event_date", searchParams.date);
    if (searchParams.employee_id) q = q.eq("employee_id", searchParams.employee_id);
    if (filteredEmployeeIds) q = q.in("employee_id", filteredEmployeeIds);
    return q;
  }
  const logsQuery = buildLogsQuery().range(from, to);
  const exportLogsQuery = buildLogsQuery().limit(EXPORT_LIMIT);

  let calLogsQuery = supabase
    .from("attendance_logs")
    .select("employee_id, event_date")
    .in("event_type", ["check_in", "check_out"])
    .gte("event_date", calMonthStart)
    .lte("event_date", calMonthEnd);
  if (filteredEmployeeIds) calLogsQuery = calLogsQuery.in("employee_id", filteredEmployeeIds);

  // Independent queries -- run concurrently rather than paying four
  // sequential Supabase round-trips back to back.
  const [
    { data: employees },
    { data: logs, count: logsCount },
    { data: exportLogs },
    { data: calLogs },
    { data: holidayRows },
  ] = await Promise.all([
    supabase.from("employees").select("id, full_name").order("full_name"),
    logsQuery,
    exportLogsQuery,
    calLogsQuery,
    supabase
      .from("holidays")
      .select("holiday_date, name")
      .gte("holiday_date", calMonthStart)
      .lte("holiday_date", calMonthEnd),
  ]);
  const holidaySet = new Set((holidayRows ?? []).map((h) => h.holiday_date));
  const holidayNameByDate = new Map((holidayRows ?? []).map((h) => [h.holiday_date, h.name]));

  const nameById = new Map((employees ?? []).map((e) => [e.id, e.full_name]));
  const rows = (logs ?? []).map((log) => ({
    ...log,
    employee_name: nameById.get(log.employee_id) ?? "Unknown",
  }));
  const exportRows = (exportLogs ?? []).map((log) => ({
    ...log,
    employee_name: nameById.get(log.employee_id) ?? "Unknown",
  }));
  const totalPages = Math.max(1, Math.ceil((logsCount ?? 0) / PAGE_SIZE));
  const pageHref = (targetPage: number) => {
    const params = new URLSearchParams(filterQuery);
    if (searchParams.date) params.set("date", searchParams.date);
    if (searchParams.employee_id) params.set("employee_id", searchParams.employee_id);
    if (searchParams.cal) params.set("cal", searchParams.cal);
    params.set("page", String(targetPage));
    return `/attendance?${params.toString()}`;
  };

  const presentByDay = new Map<number, Set<string>>();
  for (const log of calLogs ?? []) {
    const day = Number(log.event_date.slice(8, 10));
    if (!presentByDay.has(day)) presentByDay.set(day, new Set());
    presentByDay.get(day)!.add(log.employee_id);
  }
  const calDayNumbers = Array.from({ length: calDaysInMonth }, (_, i) => i + 1);
  const maxDayCount = Math.max(1, ...calDayNumbers.map((d) => presentByDay.get(d)?.size ?? 0));
  const today = todayIso();

  function calLink(dateStr: string, monthValue: string) {
    const params = new URLSearchParams(filterQuery);
    params.set("date", dateStr);
    params.set("cal", monthValue);
    if (searchParams.employee_id) params.set("employee_id", searchParams.employee_id);
    return `/attendance?${params.toString()}`;
  }

  function calMonthLink(monthValue: string) {
    const params = new URLSearchParams(filterQuery);
    if (searchParams.date) params.set("date", searchParams.date);
    if (searchParams.employee_id) params.set("employee_id", searchParams.employee_id);
    params.set("cal", monthValue);
    return `/attendance?${params.toString()}`;
  }

  const calCells: CalendarCell[] = calDayNumbers.map((d) => {
    const count = presentByDay.get(d)?.size ?? 0;
    const dateStr = `${calMonthValue}-${pad(d)}`;
    if (isNonWorkingDay(calYear, calMonth, d, holidaySet)) {
      return {
        day: d,
        href: calLink(dateStr, calMonthValue),
        label: holidayNameByDate.get(dateStr) ?? "NA",
        tone: "na",
        isSelected: searchParams.date === dateStr,
        isToday: dateStr === today,
      };
    }
    let tone: CalendarCell["tone"] = "empty";
    if (count > 0) {
      const ratio = count / maxDayCount;
      tone = ratio > 0.66 ? "high" : ratio > 0.33 ? "mid" : "low";
    }
    return {
      day: d,
      href: calLink(dateStr, calMonthValue),
      label: count > 0 ? String(count) : undefined,
      tone,
      isSelected: searchParams.date === dateStr,
      isToday: dateStr === today,
    };
  });

  return (
    <div className="space-y-6">
      <AutoRefresh />
      {searchParams.error && (
        <p className="rounded-md bg-red-50 px-3 py-2 text-sm text-red-700">{searchParams.error}</p>
      )}
      <div className="flex items-center justify-between">
        <h1 className="text-lg font-semibold text-slate-900">Attendance log</h1>
        <div className="flex items-center gap-4">
          <Link
            href="/attendance/register"
            className="text-sm font-medium text-indigo-600 hover:text-indigo-700"
          >
            Monthly register →
          </Link>
          <ExportCsvButton rows={exportRows} />
        </div>
      </div>

      <div className="flex flex-col gap-4 lg:flex-row lg:items-start">
        <div className="w-full shrink-0 space-y-2 lg:w-72">
          <MonthCalendar
            year={calYear}
            month={calMonth}
            cells={calCells}
            title={calMonthLabel}
            prevHref={calMonthLink(prevCalValue)}
            nextHref={calMonthLink(nextCalValue)}
          />
          {searchParams.date && (
            <Link
              href={(() => {
                const params = new URLSearchParams(filterQuery);
                if (searchParams.employee_id) params.set("employee_id", searchParams.employee_id);
                const qs = params.toString();
                return `/attendance${qs ? `?${qs}` : ""}`;
              })()}
              className="block text-center text-xs text-slate-500 hover:text-slate-900"
            >
              Clear date filter
            </Link>
          )}
        </div>

        <div className="flex-1 space-y-6">
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
                Student
              </label>
              <select
                id="employee_id"
                name="employee_id"
                defaultValue={searchParams.employee_id ?? ""}
                className="rounded-md border border-slate-300 px-2 py-1.5"
              >
                <option value="">All students</option>
                {employees?.map((e) => (
                  <option key={e.id} value={e.id}>
                    {e.full_name}
                  </option>
                ))}
              </select>
            </div>
            <StudentFilterFields
              departments={departments}
              standards={standards}
              sections={sections}
              filters={filters}
            />
            <button
              type="submit"
              className="self-end rounded-md bg-indigo-600 px-3 py-1.5 font-medium text-white hover:bg-indigo-500"
            >
              Filter
            </button>
          </form>

          <div className="overflow-hidden rounded-xl border border-slate-200 bg-white">
            <table className="w-full text-sm">
              <thead className="border-b border-slate-200 bg-slate-50 text-left text-slate-500">
                <tr>
                  <th className="px-4 py-3 font-medium">Student</th>
                  <th className="px-4 py-3 font-medium">Event</th>
                  <th className="px-4 py-3 font-medium">Date</th>
                  <th className="px-4 py-3 font-medium">Time</th>
                  <th className="px-4 py-3 font-medium">Confidence</th>
                  <th className="px-4 py-3 font-medium" />
                </tr>
              </thead>
              <tbody>
                {rows.map((row) => (
                  <tr key={row.id} className="border-b border-slate-100 last:border-0">
                    <td className="px-4 py-3 font-medium text-slate-900">{row.employee_name}</td>
                    <td className="px-4 py-3 text-slate-600">{eventTypeLabel(row.event_type)}</td>
                    <td className="px-4 py-3 text-slate-600">{row.event_date}</td>
                    <td className="px-4 py-3 text-slate-600">
                      {formatTime(row.scanned_at)}
                    </td>
                    <td className="px-4 py-3 text-slate-600">
                      {row.confidence != null ? row.confidence.toFixed(2) : "-"}
                    </td>
                    <td className="px-4 py-3 text-right">
                      <DeleteLogButton logId={row.id} label={eventTypeLabel(row.event_type)} />
                    </td>
                  </tr>
                ))}
                {rows.length === 0 && (
                  <tr>
                    <td colSpan={6} className="px-4 py-8 text-center text-slate-400">
                      No attendance records match this filter.
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>

          {totalPages > 1 && (
            <div className="flex items-center justify-between text-sm text-slate-600">
              <Link
                href={pageHref(page - 1)}
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
                href={pageHref(page + 1)}
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
      </div>
    </div>
  );
}
