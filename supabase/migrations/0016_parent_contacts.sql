-- Parent/guardian contact details on the student registration form, so an
-- admin can later notify a parent when their child is marked present or
-- absent. This migration only adds the columns -- no notification sending
-- happens here; that's a separate integration (the user is wiring it up
-- externally, e.g. via Google Sheets) to be connected once a channel is
-- chosen. All columns are optional (nullable): not every student will have
-- both a mother's and father's contact on file, and existing rows have
-- neither.
alter table public.employees
  add column mother_name text,
  add column mother_phone text,
  add column mother_email text,
  add column father_name text,
  add column father_phone text,
  add column father_email text;
