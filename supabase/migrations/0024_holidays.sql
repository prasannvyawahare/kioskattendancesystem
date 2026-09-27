-- Admin-managed list of non-working dates. Every Sunday is already treated
-- as a holiday in application code (admin_panel's date-utils.ts /
-- attendance-status.ts) without needing a row here -- this table only holds
-- the *extra* one-off holidays (festivals, closures, etc). Attendance
-- register/reports and calendars mark these dates "NA" instead of
-- Present/Absent and exclude them from the presence-percentage denominator.
create table public.holidays (
  id uuid primary key default gen_random_uuid(),
  holiday_date date not null unique,
  name text not null default 'Holiday',
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete set null
);

alter table public.holidays enable row level security;

-- Admins have full CRUD. No kiosk policy -- the kiosk app never reads this
-- table, only the admin panel does.
create policy "holidays_admin_all"
  on public.holidays for all
  using (public.current_user_role() = 'admin')
  with check (public.current_user_role() = 'admin');
