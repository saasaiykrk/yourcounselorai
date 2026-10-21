-- Plans bought outside the app (a funnel, a landing page, Zapier/Make/Pabbly...), reported by
-- POST /v1/webhooks/purchase with a shared secret. One row per purchase event (event_id is unique, so a
-- repeated delivery never grants twice). A purchase for an email with no YourCounselor account yet waits
-- ('pending') and is applied when that person signs up with the same email. Applied purchases also become
-- paid billing_orders (provider 'external') so they appear in Payments. Safe to run again.
create table if not exists external_purchases (
  id            bigserial primary key,
  event_id      text not null unique check (char_length(event_id) between 1 and 160),
  source        text not null default '' check (char_length(source) <= 60),
  email         text not null check (char_length(email) <= 254),
  plan          text not null check (plan in ('learn','practice','byok_scale','scale','per_report')),
  period        text check (period in ('month','year')),
  report_type   text check (report_type in ('guided','direct')),
  amount        int  not null default 0 check (amount >= 0),
  currency      text not null default 'INR',
  payment_ref   text check (char_length(payment_ref) <= 120),
  status        text not null default 'pending' check (status in ('pending','applied','cancelled')),
  clinician_id  uuid references clinicians(id),
  order_id      uuid references billing_orders(id),
  note          text,
  created_at    timestamptz not null default now(),
  applied_at    timestamptz,
  check ((plan in ('learn','practice','byok_scale','scale')) = (period is not null)),
  check ((plan = 'per_report') = (report_type is not null))
);
create index if not exists external_purchases_pending_idx on external_purchases (lower(email)) where status = 'pending';
create index if not exists external_purchases_created_idx on external_purchases (created_at desc);
