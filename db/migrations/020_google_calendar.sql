-- 020: Google Calendar and Google Meet for bookings. A consultant connects their own Google account once (OAuth,
-- scope calendar.events); every confirmed appointment then gets an event on their primary calendar, with a Google
-- Meet link when their choice allows it (meet_for: only appointments tagged Online, or all), and the client invited.
-- The refresh token is stored only AES-256-GCM sealed under BYOK_ENCRYPTION_KEY (like clinicians' own AI keys),
-- never returned, logged or shown. Nothing clinical goes to Google: the consultant's display name, the time and
-- the client's email (the booking page asks consent for this).
-- Run once in the Supabase SQL Editor, before deploying the backend that reads it. Safe to run again.
create table if not exists google_connections (
  clinician_id  uuid primary key references clinicians(id) on delete cascade,
  google_email  text not null,
  ciphertext    bytea not null,
  nonce         bytea not null,
  key_version   int not null,
  meet_for      text not null default 'online' check (meet_for in ('online', 'all')),
  status        text not null default 'ok' check (status in ('ok', 'revoked')),
  last_error    text,
  connected_at  timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
alter table google_connections enable row level security;

-- Per appointment: the Google event and its Meet link. google_sync: 'pending' = the event must be created, moved
-- or deleted (done right after the booking, retried by the scheduled delivery); 'done'; 'none' (no connection);
-- 'failed' (gave up after repeated errors).
alter table appointments add column if not exists google_event_id text;
alter table appointments add column if not exists meet_url text;
alter table appointments add column if not exists google_sync text not null default 'none'
  check (google_sync in ('none', 'pending', 'done', 'failed'));
alter table appointments add column if not exists google_attempts int not null default 0;
create index if not exists appointments_google_sync on appointments (google_sync) where google_sync = 'pending';
