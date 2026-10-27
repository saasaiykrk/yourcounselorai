-- 017: the clinician's own mobile number, asked at registration (+<country code><number>, e.g. +919876543210).
-- Used to contact them about their account and, as the Data Processing Agreement says, for offers and updates.
-- Never a client's number; never sent to the AI. Blanked when the account is deleted.
-- Run once in the Supabase SQL Editor, before deploying the backend that writes it.
alter table clinicians add column if not exists mobile text;
