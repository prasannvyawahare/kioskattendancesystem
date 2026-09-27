// The department/standard/section <select> trio, shared by the attendance
// log, monthly register, and reports filter forms so the three stay visually
// and behaviorally identical.

function FilterSelect({
  label,
  name,
  value,
  options,
  allLabel,
}: {
  label: string;
  name: string;
  value?: string;
  options: string[];
  allLabel: string;
}) {
  return (
    <div className="space-y-1">
      <label htmlFor={name} className="block text-xs font-medium text-slate-600">
        {label}
      </label>
      <select
        id={name}
        name={name}
        defaultValue={value ?? ""}
        className="rounded-md border border-slate-300 px-2 py-1.5"
      >
        <option value="">{allLabel}</option>
        {options.map((option) => (
          <option key={option} value={option}>
            {option}
          </option>
        ))}
      </select>
    </div>
  );
}

export function StudentFilterFields({
  departments,
  standards,
  sections,
  department,
  standard,
  section,
}: {
  departments: string[];
  standards: string[];
  sections: string[];
  department?: string;
  standard?: string;
  section?: string;
}) {
  return (
    <>
      <FilterSelect
        label="Department"
        name="department"
        value={department}
        options={departments}
        allLabel="All departments"
      />
      <FilterSelect
        label="Standard"
        name="standard"
        value={standard}
        options={standards}
        allLabel="All standards"
      />
      <FilterSelect
        label="Section"
        name="section"
        value={section}
        options={sections}
        allLabel="All sections"
      />
    </>
  );
}
