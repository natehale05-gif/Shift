-- The key vault.
--
-- Two kinds of key live here, and the distinction is the whole product
-- decision: `user` keys belong to the account that added them, `managed` keys
-- are SHIFT's own, spent on behalf of a paying member.
--
-- The ciphertext is never readable by a client. Row security alone cannot say
-- that — it filters rows, not columns — so the column privilege below is what
-- actually enforces it, and the `provider_key_metadata` view is what a client
-- is expected to read instead.
create table if not exists provider_keys (
  id         uuid primary key default gen_random_uuid(),
  owner_id   uuid not null references profiles(id) on delete cascade,
  provider   text not null,
  -- 'user'    — the member's own key, added in Settings
  -- 'managed' — SHIFT's key, spent under a membership
  key_owner  text not null check (key_owner in ('user', 'managed')),
  -- Encrypted with a KMS-held key and decrypted only inside an edge function.
  -- Storing plaintext here would make one database read someone else's bill.
  ciphertext bytea not null,
  -- Which KMS key encrypted it, so a rotation can find what still needs
  -- re-wrapping instead of guessing.
  kms_key_id text not null,
  -- Enough to recognise a key without revealing it.
  last_four  text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (owner_id, provider, key_owner)
);

create index if not exists provider_keys_owner_idx on provider_keys (owner_id);

alter table provider_keys enable row level security;
alter table provider_keys force row level security;

-- A member may see *that* they have a key, and delete it. Adding and reading
-- one both go through an edge function holding the service role, because both
-- touch the secret.
drop policy if exists provider_keys_select_own on provider_keys;
create policy provider_keys_select_own on provider_keys
  for select using (owner_id = shift.current_user_id());

drop policy if exists provider_keys_delete_own on provider_keys;
create policy provider_keys_delete_own on provider_keys
  for delete using (owner_id = shift.current_user_id());

grant select (id, owner_id, provider, key_owner, last_four, created_at, updated_at)
  on provider_keys to authenticated;
grant delete on provider_keys to authenticated;
grant all on provider_keys to service_role;

-- What a client is meant to read. `security_invoker` so the caller's row
-- policies still apply — a view that ran as its owner would be a hole straight
-- through the policies above.
create or replace view provider_key_metadata
  with (security_invoker = true)
as
  select id, owner_id, provider, key_owner, last_four, created_at
  from provider_keys;

grant select on provider_key_metadata to authenticated;
