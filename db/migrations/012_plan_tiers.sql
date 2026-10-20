-- Learn / Practice / BYOK Scale / Scale plans, prepaid by the month or the year (app/billing.py).
-- * An order and its entitlement name the period ('month' or 'year'). Learn's free months are an
--   entitlement with period 'trial', at most one per clinician. An admin grant has period 'admin'.
-- * Scale's AI-Guided reports come in monthly allowances: entitlements with period 'allowance' whose
--   parent_id is the Scale entitlement; a refund or deactivation of the plan cancels them too.
-- * "scale_extra" is one more AI-Guided report for someone on Scale.
-- The retired plans (sub_30, sub_50, byok) stay allowed so their old orders and grants keep their history.
-- Safe to run again.
alter table billing_orders add column if not exists period text;
alter table entitlements   add column if not exists period text;
alter table entitlements   add column if not exists parent_id uuid references entitlements(id);

alter table billing_orders drop constraint if exists billing_orders_plan_check;
alter table billing_orders add constraint billing_orders_plan_check
  check (plan in ('per_report','sub_30','sub_50','byok','print','learn','practice','byok_scale','scale','scale_extra'));
alter table entitlements drop constraint if exists entitlements_plan_check;
alter table entitlements add constraint entitlements_plan_check
  check (plan in ('per_report','sub_30','sub_50','byok','manual','print','learn','practice','byok_scale','scale',
                  'scale_extra'));

alter table billing_orders drop constraint if exists billing_orders_period_check;
alter table billing_orders add constraint billing_orders_period_check
  check ((plan in ('learn','practice','byok_scale','scale')) = (period is not null) and
         (period is null or period in ('month','year')));
alter table entitlements drop constraint if exists entitlements_period_check;
alter table entitlements add constraint entitlements_period_check
  check (period is null or period in ('month','year','trial','admin','allowance'));

create unique index if not exists entitlements_one_trial on entitlements (clinician_id) where period = 'trial';
create index if not exists entitlements_tier_idx on entitlements (clinician_id, plan, expires_at)
  where plan in ('learn','practice','byok_scale','scale');
create index if not exists entitlements_parent_idx on entitlements (parent_id) where parent_id is not null;
