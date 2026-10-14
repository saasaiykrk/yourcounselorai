-- The app's request id on each direct-consult turn, so a reply that finished while the phone was
-- disconnected (app in the background) can be fetched again instead of being paid for twice.
-- Safe to run again.
alter table turns add column if not exists request_id text;
create unique index if not exists turns_clinician_request_id on turns (clinician_id, request_id)
  where request_id is not null;
