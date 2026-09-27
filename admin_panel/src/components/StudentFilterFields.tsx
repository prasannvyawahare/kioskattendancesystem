// Single combined Department/Standard/Section quick filter, shared by the
// attendance log, monthly register, reports, and students pages so the four
// stay visually and behaviorally identical. One <select> rather than three
// -- values are "field:value" (see lib/student-filters.ts), grouped by
// field via <optgroup> so the admin still only ever picks from a real,
// known value (no free typing).

import type { StudentFilters } from "@/lib/student-filters";
import { combinedFilterValue } from "@/lib/student-filters";

function OptGroup({ label, field, values }: { label: string; field: string; values: string[] }) {
  if (values.length === 0) return null;
  return (
    <optgroup label={label}>
      {values.map((value) => (
        <option key={value} value={`${field}:${value}`}>
          {value}
        </option>
      ))}
    </optgroup>
  );
}

export function StudentFilterFields({
  departments,
  standards,
  sections,
  filters,
}: {
  departments: string[];
  standards: string[];
  sections: string[];
  filters: StudentFilters;
}) {
  return (
    <div className="space-y-1">
      <label htmlFor="filter" className="block text-xs font-medium text-slate-600">
        Filter
      </label>
      <select
        id="filter"
        name="filter"
        defaultValue={combinedFilterValue(filters)}
        className="rounded-md border border-slate-300 px-2 py-1.5"
      >
        <option value="">All students</option>
        <OptGroup label="Departments" field="department" values={departments} />
        <OptGroup label="Standards" field="standard" values={standards} />
        <OptGroup label="Sections" field="section" values={sections} />
      </select>
    </div>
  );
}
