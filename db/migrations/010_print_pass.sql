-- Single print: Print / Save as PDF for one education page, for a few hours (24 by default), bought
-- from that page. An order and its entitlement name the page in `item` (the page's slug); the
-- entitlement grants no credits and ends at expires_at. Safe to run again.
alter table billing_orders add column if not exists item text;
alter table entitlements   add column if not exists item text;

alter table billing_orders drop constraint if exists billing_orders_plan_check;
alter table billing_orders add constraint billing_orders_plan_check
  check (plan in ('per_report','sub_30','sub_50','byok','print'));
alter table entitlements drop constraint if exists entitlements_plan_check;
alter table entitlements add constraint entitlements_plan_check
  check (plan in ('per_report','sub_30','sub_50','byok','manual','print'));

-- A single print always names its page; nothing else does.
alter table billing_orders drop constraint if exists billing_orders_print_item;
alter table billing_orders add constraint billing_orders_print_item
  check ((plan = 'print') = (item is not null));
alter table entitlements drop constraint if exists entitlements_print_item;
alter table entitlements add constraint entitlements_print_item
  check ((plan = 'print') = (item is not null));

create index if not exists entitlements_print_idx on entitlements (clinician_id, item, expires_at)
  where plan = 'print';
