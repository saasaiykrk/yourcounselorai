-- 016: which email address each clinician has proved they own.
-- Sign-up needs no confirmation email (Supabase "Confirm email" off: the 6-digit code is the only email), so an
-- account's address alone proves nothing: a password sign-up or an email change takes effect without a code.
-- The backend records the address here only when the clinician opens the app with a session that came from an
-- emailed code (`amr` otp/magiclink in the login token). Plans bought in a funnel (external_purchases) go only
-- to an account whose proven address is its current sign-in address.
-- Run once in the Supabase SQL Editor, before deploying the backend that reads it.
alter table clinicians add column if not exists proven_email text;
