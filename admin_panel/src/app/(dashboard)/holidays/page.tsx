import { createClient } from "@/lib/supabase/server";
import { addHoliday, deleteHoliday } from "./actions";

export default async function HolidaysPage({
  searchParams,
}: {
  searchParams: { error?: string; saved?: string };
}) {
  const supabase = createClient();
  const { data: holidays } = await supabase
    .from("holidays")
    .select("id, holiday_date, name")
    .order("holiday_date");

  const today = new Date().toISOString().slice(0, 10);
  const upcoming = (holidays ?? []).filter((h) => h.holiday_date >= today);
  const past = (holidays ?? []).filter((h) => h.holiday_date < today);

  return (
    <div className="max-w-2xl space-y-6">
      <div>
        <h1 className="text-lg font-semibold text-slate-900">Holidays</h1>
        <p className="mt-1 text-sm text-slate-500">
          Every Sunday is already treated as a non-working day automatically. Add any other dates
          here (festivals, closures, etc) -- the attendance register, calendars, and reports mark
          them <span className="font-medium">NA</span> instead of Present/Absent and leave them
          out of the presence-percentage calculation.
        </p>
      </div>

      {searchParams.error && (
        <p className="rounded-md bg-red-50 px-3 py-2 text-sm text-red-700">{searchParams.error}</p>
      )}
      {searchParams.saved && (
        <p className="rounded-md bg-emerald-50 px-3 py-2 text-sm text-emerald-700">Saved.</p>
      )}

      <form
        action={addHoliday}
        className="flex flex-wrap items-end gap-3 rounded-xl border border-slate-200 bg-white p-4 text-sm"
      >
        <div className="space-y-1">
          <label htmlFor="holiday_date" className="block text-xs font-medium text-slate-600">
            Date
          </label>
          <input
            id="holiday_date"
            name="holiday_date"
            type="date"
            required
            className="rounded-md border border-slate-300 px-2 py-1.5"
          />
        </div>
        <div className="space-y-1">
          <label htmlFor="holiday_name" className="block text-xs font-medium text-slate-600">
            Name
          </label>
          <input
            id="holiday_name"
            name="name"
            type="text"
            placeholder="e.g. Diwali"
            className="rounded-md border border-slate-300 px-2 py-1.5"
          />
        </div>
        <button
          type="submit"
          className="rounded-md bg-indigo-600 px-3 py-1.5 font-medium text-white hover:bg-indigo-500"
        >
          Add holiday
        </button>
      </form>

      <div className="rounded-xl border border-slate-200 bg-white p-4">
        <h2 className="text-sm font-semibold text-slate-900">Upcoming &amp; today</h2>
        <HolidayList holidays={upcoming} emptyLabel="No upcoming holidays added yet." />
      </div>

      {past.length > 0 && (
        <div className="rounded-xl border border-slate-200 bg-white p-4">
          <h2 className="text-sm font-semibold text-slate-900">Past</h2>
          <HolidayList holidays={past} emptyLabel="No past holidays." />
        </div>
      )}
    </div>
  );
}

function HolidayList({
  holidays,
  emptyLabel,
}: {
  holidays: { id: string; holiday_date: string; name: string }[];
  emptyLabel: string;
}) {
  if (holidays.length === 0) {
    return <p className="mt-2 text-xs text-slate-400">{emptyLabel}</p>;
  }
  return (
    <ul className="mt-2 divide-y divide-slate-100 text-sm">
      {holidays.map((h) => (
        <li key={h.id} className="flex items-center justify-between py-2">
          <span>
            <span className="font-medium text-slate-900">{h.holiday_date}</span>{" "}
            <span className="text-slate-500">{h.name}</span>
          </span>
          <form action={deleteHoliday}>
            <input type="hidden" name="id" value={h.id} />
            <button type="submit" className="text-xs text-red-600 hover:text-red-700">
              Remove
            </button>
          </form>
        </li>
      ))}
    </ul>
  );
}
