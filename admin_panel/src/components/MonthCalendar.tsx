import Link from "next/link";

export type CalendarCell = {
  day: number;
  href?: string;
  label?: string;
  tone?: "empty" | "low" | "mid" | "high";
  isSelected?: boolean;
  isToday?: boolean;
};

const TONE_CLASSES: Record<NonNullable<CalendarCell["tone"]>, string> = {
  empty: "bg-slate-50 text-slate-300",
  low: "bg-red-50 text-red-700",
  mid: "bg-amber-50 text-amber-700",
  high: "bg-emerald-50 text-emerald-700",
};

const WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

export function MonthCalendar({
  year,
  month, // 1-12
  cells,
}: {
  year: number;
  month: number;
  cells: CalendarCell[];
}) {
  const firstWeekday = new Date(year, month - 1, 1).getDay();
  const daysInMonth = new Date(year, month, 0).getDate();
  const cellByDay = new Map(cells.map((c) => [c.day, c]));
  const leading = Array.from({ length: firstWeekday });
  const days = Array.from({ length: daysInMonth }, (_, i) => i + 1);

  return (
    <div className="rounded-xl border border-slate-200 bg-white p-3">
      <div className="grid grid-cols-7 gap-1 text-center text-[11px] font-medium text-slate-400">
        {WEEKDAYS.map((w) => (
          <div key={w} className="py-1">
            {w}
          </div>
        ))}
      </div>
      <div className="grid grid-cols-7 gap-1">
        {leading.map((_, i) => (
          <div key={`lead-${i}`} />
        ))}
        {days.map((day) => {
          const cell = cellByDay.get(day);
          const tone = cell?.tone ?? "empty";
          const inner = (
            <div
              className={`flex h-12 flex-col items-center justify-center rounded-md text-xs transition-opacity ${TONE_CLASSES[tone]} ${
                cell?.isSelected ? "ring-2 ring-indigo-500" : ""
              } ${cell?.isToday ? "font-semibold" : ""}`}
            >
              <span>{day}</span>
              {cell?.label && <span className="mt-0.5 text-[10px] leading-none">{cell.label}</span>}
            </div>
          );
          return (
            <div key={day}>
              {cell?.href ? (
                <Link href={cell.href} className="block hover:opacity-70">
                  {inner}
                </Link>
              ) : (
                inner
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
}
