// Shared helpers for the department/standard/section filter trio used on
// the attendance log, monthly register, and reports pages.

export type StudentFilters = {
  department?: string;
  standard?: string;
  section?: string;
};

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

// Renders the trio back onto a query string, e.g. for pagination/prev-next
// links that need to preserve the current filter selection without a form
// submit.
export function filterQueryString(filters: StudentFilters): string {
  const params = new URLSearchParams();
  if (filters.department) params.set("department", filters.department);
  if (filters.standard) params.set("standard", filters.standard);
  if (filters.section) params.set("section", filters.section);
  return params.toString();
}
