-- Clinician's own name, gender and age, asked at registration (run once in Supabase → SQL Editor;
-- safe to run again). These describe the CLINICIAN, never a client; they are shown only to admins
-- (to check against the RCI / medical council register) and are never sent to the AI.
alter table clinicians add column if not exists full_name text
  check (char_length(full_name) between 2 and 100);
alter table clinicians add column if not exists gender text
  check (gender in ('female','male','other','prefer_not_to_say'));
alter table clinicians add column if not exists age_at_registration int
  check (age_at_registration between 18 and 100);
