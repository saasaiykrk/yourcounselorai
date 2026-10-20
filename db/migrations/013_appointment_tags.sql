-- Appointment tags: one of First Session, Follow-up or Online (or none). The client picks it on the
-- booking page; the consultant can set or change it in the app. Not client details: it names the kind of
-- session only, so it is stored plainly, like the times. Safe to run again.
alter table appointments add column if not exists tag text;
alter table appointments drop constraint if exists appointments_tag_check;
alter table appointments add constraint appointments_tag_check
  check (tag is null or tag in ('first_session','follow_up','online'));
