import Link from "next/link";

export type CalendarCell = {
  day: number;
  href?: string;
  label?: string;
  tone?: "empty" | "low" | "mid" | "high" | "na";
  isSelected?: boolean;
  isToday?: boolean;
};

const TONE_CLASSES: Record<NonNullable<CalendarCell["tone"]>, string> = {
  empty: "text-slate-400",
  low: "bg-rose-100 text-rose-700",
  mid: "bg-amber-100 text-amber-700",
  high: "bg-emerald-100 text-emerald-700",
  na: "bg-slate-100 text-slate-400",
};

const TONE_LABEL_CLASSES: Record<NonNullable<CalendarCell["tone"]>, string> = {
  empty: "text-slate-300",
  low: "text-rose-500",
  mid: "text-amber-600",
  high: "text-emerald-600",
  na: "text-slate-400",
};

const WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

function ChevronIcon({ direction }: { direction: "left" | "right" }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" strokeWidth={2} className="h-4 w-4">
      <path
        d={direction === "left" ? "M14.5 5.5l-6.5 6.5 6.5 6.5" : "M9.5 5.5l6.5 6.5-6.5 6.5"}
        stroke="currentColor"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}

export function MonthCalendar({
  year,
  month, // 1-12
  cells,
  title,
  prevHref,
  nextHref,
}: {
  year: number;
  month: number;
  cells: CalendarCell[];
  /** Optional header label shown between the nav arrows, e.g. "October 2025". */
  title?: string;
  /** When provided, renders a built-in header with prev/next month links. */
  prevHref?: string;
  nextHref?: string;
}) {
  const firstWeekday = new Date(year, month - 1, 1).getDay();
  const daysInMonth = new Date(year, month, 0).getDate();
  const cellByDay = new Map(cells.map((c) => [c.day, c]));
  const leading = Array.from({ length: firstWeekday });
  const days = Array.from({ length: daysInMonth }, (_, i) => i + 1);

  return (
    <div className="rounded-2xl border border-slate-100 bg-white p-4 shadow-sm shadow-slate-200/60">
      {(title || prevHref || nextHref) && (
        <div className="mb-3 flex items-center justify-between">
          {prevHref ? (
            <Link
              href={prevHref}
              className="flex h-7 w-7 items-center justify-center rounded-full text-slate-400 hover:bg-slate-100 hover:text-slate-700"
            >
              <ChevronIcon direction="left" />
            </Link>
          ) : (
            <span className="h-7 w-7" />
          )}
          <span className="text-sm font-semibold text-slate-900">{title}</span>
          {nextHref ? (
            <Link
              href={nextHref}
              className="flex h-7 w-7 items-center justify-center rounded-full text-slate-400 hover:bg-slate-100 hover:text-slate-700"
            >
              <ChevronIcon direction="right" />
            </Link>
          ) : (
            <span className="h-7 w-7" />
          )}
        </div>
      )}
      <div className="grid grid-cols-7 gap-y-1 text-center text-[11px] font-medium uppercase tracking-wide text-slate-400">
        {WEEKDAYS.map((w) => (
          <div key={w} className="py-1">
            {w.slice(0, 3)}
          </div>
        ))}
      </div>
      <div className="grid grid-cols-7 gap-y-1.5">
        {leading.map((_, i) => (
          <div key={`lead-${i}`} />
        ))}
        {days.map((day) => {
          const cell = cellByDay.get(day);
          const tone = cell?.tone ?? "empty";
          const inner = (
            <div className="flex flex-col items-center gap-0.5">
              <span
                className={`flex h-8 w-8 items-center justify-center rounded-full text-xs font-medium transition-colors ${
                  cell?.isSelected
                    ? "bg-violet-600 text-white shadow-sm shadow-violet-300"
                    : `${TONE_CLASSES[tone]} ${cell?.isToday ? "ring-2 ring-violet-400 ring-offset-1" : ""}`
                } ${cell?.isToday && !cell?.isSelected ? "font-semibold" : ""}`}
              >
                {day}
              </span>
              {cell?.label && (
                <span
                  className={`max-w-[2.75rem] truncate text-[9px] leading-none ${
                    cell?.isSelected ? "text-violet-600" : TONE_LABEL_CLASSES[tone]
                  }`}
                >
                  {cell.label}
                </span>
              )}
            </div>
          );
          return (
            <div key={day} className="flex justify-center">
              {cell?.href ? (
                <Link href={cell.href} className="rounded-full hover:opacity-80">
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
