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
      .select("id, full_name, department, gender")
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
  const boyCount = roster.filter((e) => e.gender === "male").length;
  const girlCount = roster.filter((e) => e.gender === "female").length;

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
    <div className="space-y-6">
      <AutoRefresh />
      <div>
        <h1 className="text-xl font-semibold text-slate-900">Dashboard</h1>
        <p className="text-sm text-slate-500">Today, {new Date().toLocaleDateString()}</p>
      </div>

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <StatCard label="Active students" value={roster.length} accent="violet" icon={<UsersIcon />} />
        <StatCard label="Time-ins today" value={checkIns} accent="emerald" icon={<CheckInIcon />} />
        <StatCard label="Time-outs today" value={checkOuts} accent="amber" icon={<CheckOutIcon />} />
        <StatCard
          label="Absent today"
          value={absentStudents.length}
          accent="rose"
          icon={<AbsentIcon />}
        />
        <StatCard label="Boys" value={boyCount} accent="blue" icon={<BoyIcon />} />
        <StatCard label="Girls" value={girlCount} accent="pink" icon={<GirlIcon />} />
      </div>

      <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
        <section className="rounded-2xl bg-white p-5 shadow-sm shadow-slate-200/60">
          <div className="mb-4 flex items-center justify-between">
            <h2 className="text-sm font-semibold text-slate-900">Absent today</h2>
            <span className="rounded-full bg-rose-50 px-2.5 py-1 text-xs font-semibold text-rose-600">
              {absentStudents.length}
            </span>
          </div>
          <ul className="max-h-80 divide-y divide-slate-100 overflow-y-auto text-sm">
            {absentStudents.map((student) => (
              <li key={student.id} className="flex items-center gap-3 py-2.5">
                <span className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-violet-50 text-xs font-semibold text-violet-700">
                  {initials(student.full_name)}
                </span>
                <Link
                  href={`/employees/${student.id}`}
                  className="flex-1 truncate font-medium text-slate-900 hover:underline"
                >
                  {student.full_name}
                </Link>
                <span className="shrink-0 rounded-full bg-slate-100 px-2.5 py-1 text-xs text-slate-500">
                  {student.department ?? "-"}
                </span>
              </li>
            ))}
            {absentStudents.length === 0 && (
              <li className="px-4 py-8 text-center text-slate-400">
                Everyone active has timed in today.
              </li>
            )}
          </ul>
        </section>

        <section className="rounded-2xl bg-white p-5 shadow-sm shadow-slate-200/60">
          <div className="mb-4 flex items-center justify-between">
            <h2 className="text-sm font-semibold text-slate-900">By department</h2>
            <span className="text-xs text-slate-400">% present today</span>
          </div>
          <ul className="space-y-4">
            {departmentRows.map(([dept, stats]) => {
              const pct = stats.active > 0 ? Math.round((stats.present / stats.active) * 100) : 0;
              return (
                <li key={dept}>
                  <div className="mb-1.5 flex items-center justify-between text-sm">
                    <span className="font-medium text-slate-900">{dept}</span>
                    <span className="text-slate-500">
                      {stats.present}/{stats.active} · {pct}%
                    </span>
                  </div>
                  <div className="h-2 w-full overflow-hidden rounded-full bg-slate-100">
                    <div
                      className="h-full rounded-full bg-violet-500"
                      style={{ width: `${pct}%` }}
                    />
                  </div>
                </li>
              );
            })}
            {departmentRows.length === 0 && (
              <li className="py-8 text-center text-slate-400">No active students yet.</li>
            )}
          </ul>
        </section>
      </div>

      <LiveAttendanceFeed initialLogs={logsWithNames} today={today} />
    </div>
  );
}

function initials(name: string) {
  const parts = name.trim().split(/\s+/);
  return ((parts[0]?.[0] ?? "") + (parts[1]?.[0] ?? "")).toUpperCase();
}

const ACCENT_CLASSES = {
  violet: "bg-gradient-to-br from-violet-500 to-violet-700 shadow-violet-500/30",
  emerald: "bg-gradient-to-br from-emerald-400 to-emerald-600 shadow-emerald-500/30",
  amber: "bg-gradient-to-br from-amber-400 to-amber-600 shadow-amber-500/30",
  rose: "bg-gradient-to-br from-rose-400 to-rose-600 shadow-rose-500/30",
  blue: "bg-gradient-to-br from-blue-400 to-blue-600 shadow-blue-500/30",
  pink: "bg-gradient-to-br from-pink-400 to-pink-600 shadow-pink-500/30",
} as const;

function StatCard({
  label,
  value,
  accent,
  icon,
}: {
  label: string;
  value: number;
  accent: keyof typeof ACCENT_CLASSES;
  icon: React.ReactNode;
}) {
  return (
    <div
      className={`relative flex items-center gap-4 overflow-hidden rounded-2xl p-5 text-white shadow-lg ${ACCENT_CLASSES[accent]}`}
    >
      <span
        className="absolute -right-4 -top-4 h-20 w-20 rounded-full bg-white/10"
        aria-hidden
      />
      <span className="flex h-12 w-12 shrink-0 items-center justify-center rounded-xl bg-white/20 backdrop-blur-sm">
        {icon}
      </span>
      <div className="relative">
        <p className="text-sm text-white/80">{label}</p>
        <p className="mt-1 text-2xl font-semibold">{value}</p>
      </div>
    </div>
  );
}

function UsersIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="none" strokeWidth={1.75} className="h-6 w-6">
      <circle cx="9" cy="8.5" r="3" stroke="currentColor" />
      <path d="M3 19c1-3.2 3.2-5 6-5s5 1.8 6 5" stroke="currentColor" strokeLinecap="round" />
      <path d="M15.5 6.5a2.5 2.5 0 010 5" stroke="currentColor" strokeLinecap="round" />
      <path d="M17 14.2c2 .4 3.3 1.9 4 4.8" stroke="currentColor" strokeLinecap="round" />
    </svg>
  );
}

function CheckInIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="none" strokeWidth={1.75} className="h-6 w-6">
      <path d="M15 3.5h3.5A1.5 1.5 0 0120 5v14a1.5 1.5 0 01-1.5 1.5H15" stroke="currentColor" strokeLinecap="round" strokeLinejoin="round" />
      <path d="M11 8l4 4-4 4M4 12h11" stroke="currentColor" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

function CheckOutIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="none" strokeWidth={1.75} className="h-6 w-6">
      <path d="M9 3.5H5.5A1.5 1.5 0 004 5v14a1.5 1.5 0 001.5 1.5H9" stroke="currentColor" strokeLinecap="round" strokeLinejoin="round" />
      <path d="M13 8l4 4-4 4M20 12H9" stroke="currentColor" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

function AbsentIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="none" strokeWidth={1.75} className="h-6 w-6">
      <circle cx="10" cy="8.5" r="3" stroke="currentColor" />
      <path d="M3.5 19c1-3.2 3.2-5 6.5-5s5.5 1.8 6.5 5" stroke="currentColor" strokeLinecap="round" />
      <path d="M17 8.5l3.5 3.5M20.5 8.5L17 12" stroke="currentColor" strokeLinecap="round" />
    </svg>
  );
}

// Mars symbol -- conventional "boys" glyph.
function BoyIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="none" strokeWidth={1.75} className="h-6 w-6">
      <circle cx="10" cy="14" r="6" stroke="currentColor" />
      <path d="M14.5 9.5L20 4M14.5 4h5.5v5.5" stroke="currentColor" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

// Venus symbol -- conventional "girls" glyph.
function GirlIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="none" strokeWidth={1.75} className="h-6 w-6">
      <circle cx="12" cy="9" r="6" stroke="currentColor" />
      <path d="M12 15v6M9 18h6" stroke="currentColor" strokeLinecap="round" />
    </svg>
  );
}
