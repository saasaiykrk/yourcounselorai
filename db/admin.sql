-- Admin tasks for the beta, run by hand in Supabase → SQL Editor.
-- There is no admin screen yet; the backend's PATCH /v1/admin/clinicians/{id}
-- does the same as block 3 once an admin can call it.
-- Replace the emails in quotes before running. Run one block at a time.


-- 1. Check the schema is in place: should list the 6 tables.
select table_name from information_schema.tables
where table_schema = 'public'
  and table_name in ('clinicians','conversations','turns','incidents','deid_rejections','admin_audit')
order by table_name;


-- 2. Make yourself the first admin. Sign in once in the app first (so your
--    email exists in Authentication → Users), then run this.
insert into clinicians (id, role, registration_body, registration_number, level,
                        verification_status, verification_note, verified_at,
                        consent_version, consent_at, is_admin)
select id, 'psychologist', 'none', null, 'L3',
       'verified', 'bootstrap admin', now(), 'beta-draft-1', now(), true
from auth.users where email = 'ADMIN_EMAIL_HERE'
on conflict (id) do update set is_admin = true;


-- 3. Approve a clinician after checking their registration (RCI/NMC/SMC register).
--    They must have submitted their profile in the app first.
--    Level: 'L1', 'L2' or 'L3'. Note: how you checked, e.g. 'RCI register, 2026-10-01'.
with target as (select id from auth.users where email = 'CLINICIAN_EMAIL_HERE'),
     actor  as (select id from auth.users where email = 'ADMIN_EMAIL_HERE'),
     upd as (
       update clinicians
          set level = 'L2', verification_status = 'verified',
              verification_note = 'RCI register, YYYY-MM-DD',
              verified_by = (select id from actor), verified_at = now()
        where id = (select id from target)
       returning id, level, verification_note
     )
insert into admin_audit (actor_id, action, target_id, detail)
select (select id from actor), 'verify', upd.id,
       jsonb_build_object('level', upd.level, 'status', 'verified', 'note', upd.verification_note)
from upd;


-- 4. Reject a clinician.
with target as (select id from auth.users where email = 'CLINICIAN_EMAIL_HERE'),
     actor  as (select id from auth.users where email = 'ADMIN_EMAIL_HERE'),
     upd as (
       update clinicians
          set level = null, verification_status = 'rejected',
              verification_note = 'reason here',
              verified_by = (select id from actor), verified_at = now()
        where id = (select id from target)
       returning id, verification_note
     )
insert into admin_audit (actor_id, action, target_id, detail)
select (select id from actor), 'verify', upd.id,
       jsonb_build_object('status', 'rejected', 'note', upd.verification_note)
from upd;


-- 5. Who is waiting for approval.
select u.email, c.role, c.registration_body, c.registration_number, c.created_at
from clinicians c join auth.users u on u.id = c.id
where c.verification_status = 'pending'
order by c.created_at;


-- Day to day, use the admin panel instead of these snippets:
--   * in the app: Account → "Admin: registrations and reports" (admins only), or
--   * in a browser: https://<your Cloud Run address>/admin
-- Both approve/reject registrations and triage reports, and write admin_audit rows.
-- Block 2 above is still how the very first admin is created.
