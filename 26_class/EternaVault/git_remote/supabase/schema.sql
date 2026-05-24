create table if not exists memories (
  id text primary key,
  owner text,
  "ownerDid" text,
  meta jsonb not null default '{}'::jsonb,
  path text,
  "createdAt" timestamptz not null default now()
);

create table if not exists vault_shares (
  heir_address text primary key,
  owner_did text,
  encrypted_share text not null,
  updated_at timestamptz not null default now()
);

create table if not exists heir_encryption_keys (
  heir_address text primary key,
  encryption_public_key text not null,
  updated_at timestamptz not null default now()
);

create index if not exists memories_meta_heirs_idx on memories using gin ((meta -> 'heirs'));
