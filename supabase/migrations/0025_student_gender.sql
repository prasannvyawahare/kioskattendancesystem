-- Captures each student's gender so the dashboard can show boy/girl counts
-- alongside the existing active/present/absent KPIs. Nullable -- existing
-- rows have no value until an admin edits them; the dashboard counts treat
-- null (and 'other') as neither.
alter table public.employees
  add column gender text check (gender in ('male', 'female', 'other'));
