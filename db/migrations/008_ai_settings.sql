-- Which AI model writes replies, and provider API keys added from the web admin (AI Model page).
-- Keys are AES-256-GCM encrypted with BYOK_ENCRYPTION_KEY (Secret Manager) before they are stored;
-- the database never holds a key in clear. Only the backend's service role reads these tables.
-- Safe to run again.

create table if not exists ai_settings (
  id           int primary key default 1 check (id = 1),     -- one row
  active_model text not null,
  updated_by   uuid references clinicians(id),
  updated_at   timestamptz not null default now()
);

create table if not exists ai_provider_keys (
  provider     text primary key check (provider in ('anthropic', 'gemini')),
  ciphertext   bytea not null,
  nonce        bytea not null,
  key_version  int not null,
  last4        text not null,
  updated_by   uuid references clinicians(id),
  updated_at   timestamptz not null default now()
);

alter table ai_settings      enable row level security;
alter table ai_provider_keys enable row level security;
