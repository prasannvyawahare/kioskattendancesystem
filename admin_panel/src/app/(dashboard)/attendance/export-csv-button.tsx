"use client";

type Row = {
  employee_name: string;
  event_type: string;
  event_date: string;
  scanned_at: string;
  confidence: number | null;
};

export function ExportCsvButton({ rows }: { rows: Row[] }) {
  function handleExport() {
    const header = ["Student", "Event", "Date", "Time", "Confidence"];
    const csvRows = rows.map((row) => [
      row.employee_name,
      row.event_type,
      row.event_date,
      new Date(row.scanned_at).toLocaleTimeString(),
      row.confidence != null ? row.confidence.toFixed(2) : "",
    ]);
    const csv = [header, ...csvRows]
      .map((line) => line.map((cell) => `"${String(cell).replace(/"/g, '""')}"`).join(","))
      .join("\n");

    const blob = new Blob([csv], { type: "text/csv;charset=utf-8;" });
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.download = `attendance-${new Date().toISOString().slice(0, 10)}.csv`;
    link.click();
    URL.revokeObjectURL(url);
  }

  return (
    <button
      type="button"
      onClick={handleExport}
      className="rounded-md border border-slate-300 px-3 py-2 text-sm font-medium text-slate-700 hover:bg-slate-50"
    >
      Export CSV
    </button>
  );
}
