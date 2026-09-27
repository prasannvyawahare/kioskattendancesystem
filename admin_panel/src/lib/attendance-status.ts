import { pad } from "@/lib/date-utils";

// A day is a non-working day (marked "NA", excluded from presence %) if it's
// a Sunday or an admin-added row in `holidays` -- see
// supabase/migrations/0024_holidays.sql. Neither the kiosk nor
// mark_attendance() knows about this; it's purely how the admin panel
// displays/aggregates attendance that's already been recorded.
export function isSunday(year: number, month: number, day: number): boolean {
  return new Date(year, month - 1, day).getDay() === 0;
}

// Display label for an attendance event -- "Time In"/"Time Out" reads better
// for a school audience than "check-in"/"check-out". Purely cosmetic: the
// underlying event_type column values ("check_in"/"check_out") are unchanged
// everywhere else (mark_attendance(), RLS, the kiosk app, offline sync).
export function eventTypeLabel(eventType: string): string {
  if (eventType === "check_in") return "Time In";
  if (eventType === "check_out") return "Time Out";
  return eventType;
}

export function isNonWorkingDay(
  year: number,
  month: number,
  day: number,
  holidaySet: ReadonlySet<string>,
): boolean {
  if (isSunday(year, month, day)) return true;
  return holidaySet.has(`${year}-${pad(month)}-${pad(day)}`);
}
