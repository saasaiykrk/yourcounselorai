-- Keep every reply the safety check held back, so an admin can see why (run once in Supabase → SQL Editor;
-- safe to run again). Only the /admin web page reads it, one incident at a time, and each view is written
-- to admin_audit. It is never sent to the app or to the AI. Until this runs, the server still works and
-- the admin page shows only the last attempt.
alter table turns add column if not exists held_back jsonb;
