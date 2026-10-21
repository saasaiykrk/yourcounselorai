-- A consultant's public booking profile: address, mobile number, links and a photo, shown on their booking
-- page only. They are the consultant's own details, given by them to be public; no client data. The photo
-- is a small image (JPEG, PNG or WebP, at most 400 KB), resized on the phone before upload. Safe to run again.
alter table booking_settings add column if not exists address text not null default '';
alter table booking_settings add column if not exists phone text not null default '';
alter table booking_settings add column if not exists links jsonb not null default '[]'::jsonb;
alter table booking_settings add column if not exists photo bytea;
alter table booking_settings add column if not exists photo_type text;
alter table booking_settings add column if not exists photo_version int not null default 0;

alter table booking_settings drop constraint if exists booking_settings_profile_check;
alter table booking_settings add constraint booking_settings_profile_check check (
  char_length(address) <= 300 and char_length(phone) <= 20 and jsonb_typeof(links) = 'array'
  and jsonb_array_length(links) <= 5
  and (photo is null or (octet_length(photo) <= 409600 and photo_type in ('image/jpeg','image/png','image/webp'))));
