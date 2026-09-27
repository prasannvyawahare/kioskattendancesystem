"use client";

import { jsPDF } from "jspdf";
import autoTable from "jspdf-autotable";

type StudentRow = {
  full_name: string;
  employee_code: string | null;
  presentCount: number;
  pct: number | null;
};

type DepartmentGroup = {
  department: string;
  activeCount: number;
  avgPct: number | null;
  students: StudentRow[];
};

export function GenerateReportPdfButton({
  monthLabel,
  groups,
}: {
  monthLabel: string;
  groups: DepartmentGroup[];
}) {
  function handleGenerate() {
    const doc = new jsPDF();
    const pageWidth = doc.internal.pageSize.getWidth();
    const pageHeight = doc.internal.pageSize.getHeight();
    const marginX = 14;

    doc.setFontSize(16);
    doc.text(`Attendance report — ${monthLabel}`, pageWidth / 2, 16, { align: "center" });

    let cursorY = 26;
    for (const group of groups) {
      // A department header needs room for itself plus at least one table
      // row below it -- push to a fresh page rather than stranding a
      // heading alone at the bottom.
      if (cursorY > pageHeight - 40) {
        doc.addPage();
        cursorY = 20;
      }

      doc.setFontSize(12);
      doc.setFont("helvetica", "bold");
      doc.text(group.department, marginX, cursorY);
      doc.setFont("helvetica", "normal");
      doc.setFontSize(9);
      doc.text(
        `${group.activeCount} student${group.activeCount === 1 ? "" : "s"} · avg ${
          group.avgPct == null ? "-" : `${group.avgPct}%`
        } present`,
        marginX,
        cursorY + 5,
      );
      cursorY += 9;

      autoTable(doc, {
        startY: cursorY,
        margin: { left: marginX, right: marginX },
        styles: { fontSize: 9 },
        headStyles: { fillColor: [79, 70, 229] },
        head: [["Student", "Code", "Present days", "%"]],
        body: group.students.map((s) => [
          s.full_name,
          s.employee_code ?? "-",
          String(s.presentCount),
          s.pct == null ? "-" : `${s.pct}%`,
        ]),
      });

      // jspdf-autotable augments the doc instance with this at runtime;
      // there's no typed accessor for it in @types/jspdf-autotable.
      cursorY = (doc as unknown as { lastAutoTable: { finalY: number } }).lastAutoTable.finalY + 14;
    }

    doc.save(`attendance-report-${monthLabel.replace(/\s+/g, "-")}.pdf`);
  }

  return (
    <button
      type="button"
      onClick={handleGenerate}
      disabled={groups.length === 0}
      className="rounded-md bg-indigo-600 px-3 py-2 text-sm font-medium text-white hover:bg-indigo-500 disabled:opacity-40"
    >
      Download PDF report
    </button>
  );
}
