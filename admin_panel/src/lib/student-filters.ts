// Shared helpers for the department/standard/section quick filter used on
// the attendance log, monthly register, reports, and students pages.
//
// The UI is a single <select> (StudentFilterFields) so only one of the three
// fields is ever active at once -- its value is "field:value" (e.g.
// "department:Science"), carried end-to-end as one ?filter= query param
// rather than three separate ones. Internally everything still works with
// the same { department?, standard?, section? } shape as before, so
// applyStudentFilters/distinctValues didn't need to change.

export type StudentFilterField = "department" | "standard" | "section";

export type StudentFilters = {
  department?: string;
  standard?: string;
  section?: string;
};

const FIELDS: StudentFilterField[] = ["department", "standard", "section"];

export function distinctValues<K extends string>(
  rows: Partial<Record<K, string | null>>[] | null | undefined,
  key: K,
): string[] {
  return Array.from(
    new Set((rows ?? []).map((r) => r[key]?.trim()).filter((v): v is string => !!v)),
  ).sort((a, b) => a.localeCompare(b));
}

// Applies the trio to a Supabase query builder -- typed loosely (rather than
// importing the real PostgrestFilterBuilder generics) since every call site
// passes a query built from a different `select()`, and all that matters
// here is that `.eq()` exists and returns the same chainable type.
export function applyStudentFilters<Q extends { eq(column: string, value: string): Q }>(
  query: Q,
  filters: StudentFilters,
): Q {
  let q = query;
  if (filters.department) q = q.eq("department", filters.department);
  if (filters.standard) q = q.eq("standard", filters.standard);
  if (filters.section) q = q.eq("section", filters.section);
  return q;
}

// Decodes the single combined "field:value" query param back into the
// filters shape the rest of the page (applyStudentFilters, grouping, etc)
// already works with.
export function parseCombinedFilter(raw: string | undefined): StudentFilters {
  if (!raw) return {};
  const separatorIndex = raw.indexOf(":");
  if (separatorIndex < 0) return {};
  const field = raw.slice(0, separatorIndex);
  const value = raw.slice(separatorIndex + 1);
  if (!value || !FIELDS.includes(field as StudentFilterField)) return {};
  return { [field]: value };
}

// Inverse of parseCombinedFilter -- what the <select>'s value/query param
// should be for the currently-active filter.
export function combinedFilterValue(filters: StudentFilters): string {
  for (const field of FIELDS) {
    const value = filters[field];
    if (value) return `${field}:${value}`;
  }
  return "";
}

// Renders the current filter back onto a query string, e.g. for
// pagination/prev-next links that need to preserve the current selection
// without a form submit.
export function filterQueryString(filters: StudentFilters): string {
  const value = combinedFilterValue(filters);
  if (!value) return "";
  return `filter=${encodeURIComponent(value)}`;
}
