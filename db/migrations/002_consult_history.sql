-- Consult history (run once in Supabase → SQL Editor; safe to run again).
-- Adds a clinician-set label and a "hidden" time to conversations. Hiding
-- removes a consult from the clinician's History; the de-identified record is
-- kept for safety audit until the 12-month retention job removes it.
alter table conversations add column if not exists title     text check (char_length(title) <= 60);
alter table conversations add column if not exists hidden_at timestamptz;
create index if not exists conversations_clinician_idx on conversations (clinician_id, created_at desc);
create index if not exists turns_conversation_idx on turns (conversation_id, created_at);
