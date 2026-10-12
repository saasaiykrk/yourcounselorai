-- Consultant calendar and public appointment booking.
-- Run once in Supabase → SQL Editor, BEFORE deploying the backend that uses it. Safe to run again.
--
-- Privacy: this is the only part of the database that holds a client's identity, and it holds the
-- minimum: a first name and an email, both encrypted by the backend (AES-256-GCM, key in Secret
-- Manager). Appointments are never linked to consultations, cases or the AI. Rows are purged
-- 90 days after the appointment (see booking_db.purge_old).

create extension if not exists btree_gist;   -- lets one constraint compare a clinician id AND a time range

-- One row per consultant: their public link and booking rules.
create table if not exists booking_settings (
  clinician_id        uuid primary key references clinicians(id) on delete cascade,
  slug                text not null unique check (slug ~ '^[a-z0-9](?:[a-z0-9-]{1,38}[a-z0-9])$'),
  enabled             boolean not null default false,
  display_name        text not null check (char_length(display_name) between 2 and 80),
  bio                 text not null default '' check (char_length(bio) <= 500),
  timezone            text not null default 'Asia/Kolkata',
  slot_minutes        int  not null default 30 check (slot_minutes in (15, 30, 45, 60)),
  buffer_minutes      int  not null default 0  check (buffer_minutes between 0 and 120),
  min_notice_minutes  int  not null default 240 check (min_notice_minutes between 0 and 20160),
  max_advance_days    int  not null default 30 check (max_advance_days between 1 and 365),
  approval            text not null default 'manual' check (approval in ('auto', 'manual')),
  updated_at          timestamptz not null default now()
);

-- Weekly working hours in the consultant's own timezone. Several windows a day = breaks between them.
create table if not exists availability_windows (
  id            bigserial primary key,
  clinician_id  uuid not null references clinicians(id) on delete cascade,
  weekday       int  not null check (weekday between 0 and 6),        -- 0 = Monday
  start_time    time not null,
  end_time      time not null,
  check (end_time > start_time)
);
create index if not exists availability_windows_clinician_idx on availability_windows (clinician_id, weekday);

-- Holidays, leave and blocked slots (absolute times; a whole day is local midnight to midnight).
create table if not exists time_off (
  id            bigserial primary key,
  clinician_id  uuid not null references clinicians(id) on delete cascade,
  starts_at     timestamptz not null,
  ends_at       timestamptz not null,
  label         text not null default '' check (char_length(label) <= 80),   -- the consultant's own note
  created_at    timestamptz not null default now(),
  check (ends_at > starts_at)
);
create index if not exists time_off_clinician_idx on time_off (clinician_id, starts_at);

-- Appointments. pending and confirmed rows hold their time (plus the buffer after them); the
-- exclusion constraint makes an overlap impossible even for two requests at the same instant.
create table if not exists appointments (
  id              uuid primary key default gen_random_uuid(),
  clinician_id    uuid not null references clinicians(id) on delete cascade,
  starts_at       timestamptz not null,
  ends_at         timestamptz not null,
  blocked_until   timestamptz not null,                    -- ends_at + buffer at booking time
  status          text not null check (status in
                    ('pending', 'confirmed', 'completed', 'cancelled', 'rejected', 'rescheduled', 'expired')),
  source          text not null check (source in ('public', 'consultant')),
  client_ct       bytea,                                   -- {"first_name","email"} sealed; null if none given
  client_nonce    bytea,
  client_key_ver  int,
  email_hash      text,                                    -- keyed hash, only to limit repeat bookings
  manage_hash     text unique,                             -- sha256 of the client's manage/cancel token
  consent_at      timestamptz,
  pending_until   timestamptz,                             -- a pending request expires (frees the slot) then
  cancelled_by    text check (cancelled_by in ('client', 'consultant', 'system')),
  rescheduled_from uuid references appointments(id),
  rescheduled_to  uuid references appointments(id),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  check (ends_at > starts_at and blocked_until >= ends_at)
);
create index if not exists appointments_clinician_idx on appointments (clinician_id, starts_at);
create index if not exists appointments_email_idx on appointments (clinician_id, email_hash);
do $$ begin
  alter table appointments add constraint appointments_no_overlap
    exclude using gist (clinician_id with =, tstzrange(starts_at, blocked_until) with &&)
    where (status in ('pending', 'confirmed'));
exception when duplicate_object or duplicate_table then null;
end $$;

-- Email notifications and reminders. Delivered by the backend when SMTP is configured; otherwise
-- recorded as not sent. Holds no client details — they are read from the appointment when sending.
create table if not exists booking_notifications (
  id              bigserial primary key,
  appointment_id  uuid not null references appointments(id) on delete cascade,
  kind            text not null check (kind in
                    ('requested', 'confirmed', 'rejected', 'cancelled', 'rescheduled', 'reminder', 'new_booking')),
  recipient       text not null check (recipient in ('client', 'consultant')),
  due_at          timestamptz not null default now(),
  status          text not null default 'pending' check (status in ('pending', 'sent', 'failed', 'not_configured')),
  attempts        int not null default 0,
  sent_at         timestamptz,
  created_at      timestamptz not null default now()
);
create index if not exists booking_notifications_due_idx on booking_notifications (status, due_at);

alter table booking_settings      enable row level security;
alter table availability_windows  enable row level security;
alter table time_off              enable row level security;
alter table appointments          enable row level security;
alter table booking_notifications enable row level security;
-- No policies: only the backend's service role reads or writes these tables.
