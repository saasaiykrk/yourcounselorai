-- YourCounselor backend — Postgres schema (Supabase, Mumbai region ap-south-1).
-- Only de-identified text is ever stored. Row Level Security is ON for every
-- table; the backend uses the service role, the phone never talks to the DB.

create extension if not exists pgcrypto;

create table clinicians (
  id                   uuid primary key,              -- = auth.users.id
  role                 text not null check (role in ('counsellor_trainee','psychologist','psychiatrist')),
  registration_body    text not null check (registration_body in ('RCI','NMC','SMC','none')),
  registration_number  text,
  level                text check (level in ('L1','L2','L3')),        -- NULL until verified by an admin
  verification_status  text not null default 'pending'
                         check (verification_status in ('pending','verified','rejected')),
  verification_note    text,                           -- how it was checked, e.g. "RCI register, 2026-09-25"
  verified_by          uuid references clinicians(id),
  verified_at          timestamptz,
  consent_version      text,                           -- Clinician Terms + DPA version accepted
  consent_at           timestamptz,
  is_admin             boolean not null default false,
  created_at           timestamptz not null default now()
);

create table conversations (
  id            uuid primary key default gen_random_uuid(),
  clinician_id  uuid not null references clinicians(id),
  title         text check (char_length(title) <= 60),   -- clinician's label; passes the identifier check
  hidden_at     timestamptz,                              -- deleted from History; kept for audit until retention
  created_at    timestamptz not null default now()
);
create index conversations_clinician_idx on conversations (clinician_id, created_at desc);

create table turns (
  id                      uuid primary key default gen_random_uuid(),
  conversation_id         uuid not null references conversations(id),
  clinician_id            uuid not null references clinicians(id),
  created_at              timestamptz not null default now(),
  requested_mode          text not null,
  level                   text not null,
  input_deid              text not null,               -- already cleaned on phone + re-checked on server
  client_redaction_counts jsonb not null default '{}', -- types only, from the phone
  output_raw              text not null,               -- incl. contract line
  output_shown            text not null,               -- exactly what the clinician saw
  status                  text not null check (status in ('delivered','blocked')),
  attempts                int  not null,
  inspector_reports       jsonb not null,              -- one per attempt
  model                   text not null,               -- pinned model id
  skill_version           text not null,               -- e.g. 2.1.1
  prompt_hash             text not null,               -- hash of full system prompt (drift detector)
  tool_calls              jsonb not null default '[]',
  verified_icd_codes      text[] not null default '{}',
  usage                   jsonb not null default '[]',
  latency_ms              int not null
);
create index on turns (clinician_id, created_at);
create index on turns (status);
create index turns_conversation_idx on turns (conversation_id, created_at);

create table incidents (
  id            uuid primary key default gen_random_uuid(),
  turn_id       uuid not null references turns(id),
  reported_by   uuid references clinicians(id),         -- NULL = automatic (inspector block)
  source        text not null check (source in ('clinician','inspector')),
  category      text not null,
  note          text,
  status        text not null default 'open' check (status in ('open','triaged','fixed','wont_fix')),
  reviewer_note text,
  created_at    timestamptz not null default now()
);

create table deid_rejections (                          -- server found identifiers the phone missed
  id            bigserial primary key,
  clinician_id  uuid not null references clinicians(id),
  types         jsonb not null,                         -- {"PHONE":1} — never the values
  created_at    timestamptz not null default now()
);

create table admin_audit (
  id         bigserial primary key,
  actor_id   uuid not null references clinicians(id),
  action     text not null,
  target_id  uuid,
  detail     jsonb,
  created_at timestamptz not null default now()
);

alter table clinicians      enable row level security;
alter table conversations   enable row level security;
alter table turns           enable row level security;
alter table incidents       enable row level security;
alter table deid_rejections enable row level security;
alter table admin_audit     enable row level security;
-- No policies for anon/authenticated roles: only the backend's service role can read/write.

-- Retention (beta): turns and incidents kept 12 months, then deleted by a scheduled job,
-- unless an incident is open. Confirm the period with the data-protection lawyer (Phase 4).
