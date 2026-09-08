"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import type { AttendanceEventType } from "@/lib/database.types";

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
    <section className="rounded-xl border border-slate-200 bg-white">
      <div className="border-b border-slate-200 px-4 py-3">
        <h2 className="text-sm font-medium text-slate-900">Live attendance feed</h2>
      </div>
      <ul className="divide-y divide-slate-100 text-sm">
        {logs.map((log) => (
          <li key={log.id} className="flex items-center justify-between px-4 py-3">
            <span className="font-medium text-slate-900">{log.employee_name}</span>
            <span className="capitalize text-slate-600">{log.event_type.replace("_", " ")}</span>
            <span className="text-slate-500">{new Date(log.scanned_at).toLocaleTimeString()}</span>
          </li>
        ))}
        {logs.length === 0 && (
          <li className="px-4 py-8 text-center text-slate-400">No attendance scans yet today.</li>
        )}
      </ul>
    </section>
  );
}
