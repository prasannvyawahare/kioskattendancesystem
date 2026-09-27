-- Class/grade ("standard") and "section" fields on the student registration
-- form, so students can be grouped the way a school actually organizes them
-- (e.g. standard "10", section "A"). Both optional (nullable): existing rows
-- have neither, and not every deployment tracks sections.
alter table public.employees
  add column standard text,
  add column section text;
