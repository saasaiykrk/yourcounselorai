-- 018: the admin's "skip verification" switch (/admin → Registrations). Off by default: every registration waits
-- for an admin to check the register and set the level. On: a registration is approved at once with the level of
-- the role the clinician chose (counsellor/trainee L1, psychologist L2, psychiatrist L3). The server sets it from
-- the clinicians row, never from a request. Every automatic approval and every switch change is in admin_audit.
-- Run once in the Supabase SQL Editor, before deploying the backend that reads it. Safe to run again.
create table if not exists registration_settings (
  id           int primary key default 1 check (id = 1),     -- one row
  auto_approve boolean not null default false,
  updated_by   uuid references clinicians(id),
  updated_at   timestamptz not null default now()
);
insert into registration_settings (id) values (1) on conflict (id) do nothing;
alter table registration_settings enable row level security;
