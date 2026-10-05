-- Guided consultations (run once in Supabase → SQL Editor; safe to run again).
-- One row per guided consultation, linked to its conversation so the finished report
-- appears in History. `state` is the compact, de-identified consultation state
-- (summary, facts, unknowns, the questions and answers); `busy_until` stops two
-- requests for the same consultation from running at once.
create table if not exists consultations (
  id            uuid primary key references conversations(id),
  clinician_id  uuid not null references clinicians(id),
  stage         text not null check (stage in ('INITIAL_CASE','QUESTIONING','INFORMATION_SUFFICIENT',
                                               'REPORT_GENERATION','COMPLETED','SAFETY_STOP')),
  state         jsonb not null default '{}',
  busy_until    timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists consultations_clinician_idx on consultations (clinician_id, updated_at desc);
alter table consultations enable row level security;
-- No policies: only the backend's service role reads or writes it.
