import { createClient } from "@/lib/supabase/server";
import { LiveAttendanceFeed } from "./live-attendance-feed";
import { AutoRefresh } from "@/components/AutoRefresh";

export default async function DashboardPage() {
  const supabase = createClient();
  const today = new Date().toISOString().slice(0, 10);

  const { data: todayLogs } = await supabase
    .from("attendance_logs")
    .select("id, employee_id, event_type, scanned_at")
    .eq("event_date", today)
    .order("scanned_at", { ascending: false });

  const employeeIds = Array.from(new Set((todayLogs ?? []).map((l) => l.employee_id)));
  const { data: employees } = employeeIds.length
    ? await supabase.from("employees").select("id, full_name").in("id", employeeIds)
    : { data: [] as { id: string; full_name: string }[] };

  const nameById = new Map((employees ?? []).map((e) => [e.id, e.full_name]));
  const logsWithNames = (todayLogs ?? []).map((log) => ({
    ...log,
    employee_name: nameById.get(log.employee_id) ?? "Unknown",
  }));

  const checkIns = todayLogs?.filter((l) => l.event_type === "check_in").length ?? 0;
  const checkOuts = todayLogs?.filter((l) => l.event_type === "check_out").length ?? 0;

  const { count: activeEmployeeCount } = await supabase
    .from("employees")
    .select("id", { count: "exact", head: true })
    .eq("is_active", true);

  return (
    <div className="space-y-8">
      <AutoRefresh />
      <div>
        <h1 className="text-lg font-semibold text-slate-900">Dashboard</h1>
        <p className="text-sm text-slate-500">Today, {new Date().toLocaleDateString()}</p>
      </div>

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
        <StatCard label="Active employees" value={activeEmployeeCount ?? 0} />
        <StatCard label="Check-ins today" value={checkIns} />
        <StatCard label="Check-outs today" value={checkOuts} />
      </div>

      <LiveAttendanceFeed initialLogs={logsWithNames} today={today} />
    </div>
  );
}

function StatCard({ label, value }: { label: string; value: number }) {
  return (
    <div className="rounded-xl border border-slate-200 bg-white p-5">
      <p className="text-sm text-slate-500">{label}</p>
      <p className="mt-2 text-2xl font-semibold text-slate-900">{value}</p>
    </div>
  );
}
