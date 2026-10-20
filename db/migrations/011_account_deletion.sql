-- Account deletion from the app (Google Play requires it). The clinician's row stays, so de-identified
-- consults kept for safety review and payment records kept for tax law still have an owner, but every
-- personal detail is removed and the sign-in (auth.users) is deleted. Safe to run again.
alter table clinicians add column if not exists deleted_at timestamptz;
alter table clinicians drop constraint if exists clinicians_verification_status_check;
alter table clinicians add constraint clinicians_verification_status_check
  check (verification_status in ('pending','verified','rejected','deleted'));
