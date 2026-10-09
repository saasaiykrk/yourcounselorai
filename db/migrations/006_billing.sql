-- Pricing plans, payments (Razorpay), report credits and "use my own Anthropic key" (BYOK).
-- Run once in Supabase → SQL Editor, BEFORE deploying the backend that uses it. Safe to run again.
--
-- Money is stored in minor units (paise for INR). Nothing here is required while pricing is
-- switched off (the default): report generation keeps working exactly as before.

-- Every saved pricing configuration, newest = current. Old versions stay for the audit trail.
create table if not exists pricing_config (
  version     bigserial primary key,
  config      jsonb not null,
  changed_by  uuid references clinicians(id),
  created_at  timestamptz not null default now()
);

-- One row per checkout. Amounts come from the server's pricing, never from the app.
create table if not exists billing_orders (
  id                  uuid primary key default gen_random_uuid(),
  clinician_id        uuid not null references clinicians(id),
  plan                text not null check (plan in ('per_report','sub_30','sub_50','byok')),
  report_type         text check (report_type in ('guided','direct')),
  amount              int  not null check (amount >= 0),
  currency            text not null,
  config_version      bigint not null,
  provider            text not null default 'razorpay',
  provider_order_id   text unique,
  provider_payment_id text unique,
  status              text not null default 'created'
                        check (status in ('created','pending','paid','failed','cancelled')),
  failure_reason      text,
  refund_status       text check (refund_status in ('pending','refunded','partial','failed')),
  refunded_amount     int  not null default 0 check (refunded_amount >= 0),
  provider_refund_id  text,
  created_at          timestamptz not null default now(),
  paid_at             timestamptz,
  updated_at          timestamptz not null default now()
);
create index if not exists billing_orders_clinician_idx on billing_orders (clinician_id, created_at desc);
create index if not exists billing_orders_status_idx on billing_orders (status, created_at desc);

-- What a clinician may use: report credits (per-report purchase, 30/50 subscriptions, admin grants)
-- or BYOK platform access. One entitlement per paid order (order_id unique) — a repeated payment
-- event can never grant twice.
create table if not exists entitlements (
  id                uuid primary key default gen_random_uuid(),
  clinician_id      uuid not null references clinicians(id),
  plan              text not null check (plan in ('per_report','sub_30','sub_50','byok','manual')),
  report_type       text check (report_type in ('guided','direct')),   -- per_report only; null = either
  credits_total     int  not null check (credits_total >= 0),
  credits_used      int  not null default 0 check (credits_used >= 0),
  credits_reserved  int  not null default 0 check (credits_reserved >= 0),
  starts_at         timestamptz not null default now(),
  expires_at        timestamptz,                                       -- null = does not expire
  status            text not null default 'active' check (status in ('active','cancelled')),
  order_id          uuid unique references billing_orders(id),
  note              text,
  created_by        uuid references clinicians(id),                    -- the admin, for manual grants
  created_at        timestamptz not null default now(),
  constraint entitlements_not_overspent check (credits_used + credits_reserved <= credits_total)
);
create index if not exists entitlements_clinician_idx on entitlements (clinician_id, status, expires_at);

-- Every credit movement: granted, reserved for a report, consumed, released after a failure,
-- expired, adjusted or revoked by an admin.
create table if not exists credit_ledger (
  id              bigserial primary key,
  clinician_id    uuid not null references clinicians(id),
  entitlement_id  uuid references entitlements(id),
  kind            text not null check (kind in ('grant','reserve','consume','release','expire','adjust','revoke')),
  amount          int  not null,
  report_type     text check (report_type in ('guided','direct')),
  request_key     text,
  order_id        uuid references billing_orders(id),
  actor_id        uuid references clinicians(id),
  reason          text,
  created_at      timestamptz not null default now()
);
-- A report request is charged at most once.
create unique index if not exists credit_ledger_consume_once
  on credit_ledger (clinician_id, request_key) where kind = 'consume';
create unique index if not exists credit_ledger_expire_once
  on credit_ledger (entitlement_id) where kind = 'expire';
create index if not exists credit_ledger_clinician_idx on credit_ledger (clinician_id, created_at desc);

-- Razorpay webhook deliveries already handled (Razorpay retries; each event is applied once).
create table if not exists payment_events (
  id                  text primary key,
  event               text not null,
  provider_order_id   text,
  provider_payment_id text,
  outcome             text,
  processed_at        timestamptz not null default now()
);

-- The clinician's own Anthropic key, encrypted (AES-256-GCM, key in Secret Manager). Never
-- returned by any endpoint: only the last 4 characters and the validation status.
create table if not exists byok_credentials (
  clinician_id  uuid primary key references clinicians(id),
  ciphertext    bytea not null,
  nonce         bytea not null,
  key_version   int   not null,
  last4         text  not null,
  status        text  not null check (status in ('valid','invalid')),
  last_error    text,
  validated_at  timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- Reports generated with the clinician's own key: counts and outcomes only, never the key or text.
create table if not exists byok_usage (
  id            bigserial primary key,
  clinician_id  uuid not null references clinicians(id),
  report_type   text not null check (report_type in ('guided','direct')),
  outcome       text not null,
  created_at    timestamptz not null default now()
);
create index if not exists byok_usage_created_idx on byok_usage (created_at desc);

alter table pricing_config    enable row level security;
alter table billing_orders    enable row level security;
alter table entitlements      enable row level security;
alter table credit_ledger     enable row level security;
alter table payment_events    enable row level security;
alter table byok_credentials  enable row level security;
alter table byok_usage        enable row level security;
-- No policies: only the backend's service role reads or writes these tables.
