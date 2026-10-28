-- 019: details a new clinician enters before the email code (app: Create account). Kept as a "started" sign-up,
-- shown in /admin → Registrations → Not finished, so the team can help people who never got or entered the code.
-- When a code sent to that email is verified, the backend turns the details into the clinicians row (once) and
-- marks the sign-up "completed". Unfinished sign-ups are deleted after 90 days; deleting the account deletes its
-- sign-up. The clinician's own details only, never a client's; never sent to the AI.
-- Run once in the Supabase SQL Editor, before deploying the backend that writes it. Safe to run again.
create table if not exists signup_leads (
  id                  bigserial primary key,
  email               text not null unique,                 -- lowercased
  full_name           text not null,
  gender              text,
  age                 int,
  role                text not null,
  registration_body   text not null,
  registration_number text,
  mobile              text,
  consent_version     text not null,
  status              text not null default 'started' check (status in ('started', 'completed')),
  clinician_id        uuid references clinicians(id) on delete set null,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  completed_at        timestamptz
);
create index if not exists signup_leads_status on signup_leads (status, updated_at desc);
alter table signup_leads enable row level security;
