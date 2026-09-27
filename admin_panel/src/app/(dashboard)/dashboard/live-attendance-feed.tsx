"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import type { AttendanceEventType } from "@/lib/database.types";
import { eventTypeLabel } from "@/lib/attendance-status";
import { formatTime } from "@/lib/date-utils";

type LogRow = {
  id: string;
  employee_id: string;
  employee_name: string;
  event_type: AttendanceEventType;
  scanned_at: string;
};

export function LiveAttendanceFeed({
  initialLogs,
  today,
}: {
  initialLogs: LogRow[];
  today: string;
}) {
  const [logs, setLogs] = useState(initialLogs);

  // AutoRefresh re-fetches the page (and this prop) every 5s, but this
  // component stays mounted the whole time -- without this, `logs` would
  // only ever grow via the realtime subscription below and never pick up
  // deletions/renames from elsewhere. Reconcile by merging: start from the
  // fresh server data, then keep any realtime-appended rows newer than the
  // freshest row the server returned (rows the next poll hasn't caught up
  // to yet), deduped by id.
  useEffect(() => {
    setLogs((prev) => {
      const freshIds = new Set(initialLogs.map((log) => log.id));
      const newestFreshScannedAt = initialLogs[0]?.scanned_at ?? "";
      const pendingRealtimeOnly = prev.filter(
        (log) => !freshIds.has(log.id) && log.scanned_at > newestFreshScannedAt,
      );
      return [...pendingRealtimeOnly, ...initialLogs];
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [initialLogs]);

  useEffect(() => {
    const supabase = createClient();

    const channel = supabase
      .channel("attendance-feed")
      .on(
        "postgres_changes",
        {
          event: "INSERT",
          schema: "public",
          table: "attendance_logs",
          filter: `event_date=eq.${today}`,
        },
        async (payload) => {
          const row = payload.new as {
            id: string;
            employee_id: string;
            event_type: AttendanceEventType;
            scanned_at: string;
          };
          const { data: employee } = await supabase
            .from("employees")
            .select("full_name")
            .eq("id", row.employee_id)
            .single();

          setLogs((prev) => [
            {
              id: row.id,
              employee_id: row.employee_id,
              employee_name: employee?.full_name ?? "Unknown",
              event_type: row.event_type,
              scanned_at: row.scanned_at,
            },
            ...prev,
          ]);
        },
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [today]);

  return (
    <section className="rounded-2xl bg-white p-5 shadow-sm shadow-slate-200/60">
      <h2 className="mb-4 text-sm font-semibold text-slate-900">Live attendance feed</h2>
      <ul className="divide-y divide-slate-100 text-sm">
        {logs.map((log) => (
          <li key={log.id} className="flex items-center gap-3 py-3">
            <span className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-violet-50 text-xs font-semibold text-violet-700">
              {initials(log.employee_name)}
            </span>
            <span className="flex-1 truncate font-medium text-slate-900">{log.employee_name}</span>
            <span
              className={`shrink-0 rounded-full px-2.5 py-1 text-xs font-medium ${
                log.event_type === "check_in"
                  ? "bg-emerald-50 text-emerald-600"
                  : "bg-amber-50 text-amber-600"
              }`}
            >
              {eventTypeLabel(log.event_type)}
            </span>
            <span className="w-16 shrink-0 text-right text-slate-500">
              {formatTime(log.scanned_at)}
            </span>
          </li>
        ))}
        {logs.length === 0 && (
          <li className="px-4 py-8 text-center text-slate-400">No attendance scans yet today.</li>
        )}
      </ul>
    </section>
  );
}

function initials(name: string) {
  const parts = name.trim().split(/\s+/);
  return ((parts[0]?.[0] ?? "") + (parts[1]?.[0] ?? "")).toUpperCase();
}
