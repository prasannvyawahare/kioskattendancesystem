"use client";

type Row = {
  full_name: string;
  presentDays: number[];
  pct: number | null;
};

export function ExportRegisterCsvButton({
  monthLabel,
  days,
  rows,
  nonWorkingDays = [],
}: {
  monthLabel: string;
  days: number[];
  rows: Row[];
  nonWorkingDays?: number[];
}) {
  function handleExport() {
    const nonWorkingSet = new Set(nonWorkingDays);
    const header = ["Student", ...days.map(String), "%"];
    const csvRows = rows.map((row) => {
      const presentSet = new Set(row.presentDays);
      return [
        row.full_name,
        ...days.map((d) => (nonWorkingSet.has(d) ? "NA" : presentSet.has(d) ? "P" : "A")),
        row.pct == null ? "" : `${row.pct}%`,
      ];
    });
    const csv = [header, ...csvRows]
      .map((line) => line.map((cell) => `"${String(cell).replace(/"/g, '""')}"`).join(","))
      .join("\n");

    const blob = new Blob([csv], { type: "text/csv;charset=utf-8;" });
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.download = `attendance-register-${monthLabel.replace(" ", "-")}.csv`;
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
