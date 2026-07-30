-- SHIFT's own provider keys — the ones a membership buys access to.
--
-- **A correction to `0003`.** That table modelled a managed key as a
-- `provider_keys` row with `key_owner = 'managed'`, which requires an
-- `owner_id`: it says the key belongs to one account. SHIFT's keys belong to
-- no account. Modelled that way, every member would need their own copy of the
-- same secret, and revoking or rotating it would mean rewriting one row per
-- member — with each copy a separate chance to miss one.
--
-- So they live here instead: one row per provider, owned by nobody, spent on
-- behalf of whoever has an active subscription and room under their ceiling.

create table if not exists platform_keys (
  id         uuid primary key default gen_random_uuid(),
  provider   text not null unique,
  ciphertext bytea not null,
  kms_key_id text not null,
  last_four  text not null,
  -- Turning a provider off is a switch rather than a delete, so the key does
  -- not have to be pasted again to turn it back on.
  enabled    boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table platform_keys enable row level security;
alter table platform_keys force row level security;

-- **No policies, deliberately.** Row security with no policy denies everything,
-- so no client role can read this table at all — not even its metadata, not
-- even an admin's. `service_role` reaches it by `bypassrls`, which means the
-- only way to touch these keys is an edge function. That is the whole point:
-- a leak here is not one member's bill, it is every member's.
revoke all on platform_keys from anon, authenticated;
grant all on platform_keys to service_role;

-- Who may add one.
--
-- Not a role, a column: the check happens server-side inside the edge function,
-- against a value only the service role can write. A client cannot make itself
-- an admin because it cannot write this table at all — `profiles` is
-- select+update for the owner, and update is narrowed below so this column is
-- not among the things they may change.
alter table profiles
  add column if not exists is_admin boolean not null default false;

-- `profiles_update_own` allowed a member to update their own row, which now
-- includes `is_admin`. Narrow the grant to the columns a person may actually
-- edit — the policy says *which rows*, the grant says *which columns*, and
-- only the pair of them says "you may rename yourself but not promote
-- yourself".
revoke update on profiles from authenticated;
grant update (display_name) on profiles to authenticated;

-- What a signed-in member is allowed to know: which providers their plan
-- covers. Not the keys, not the last four — a member has no use for either,
-- and the fewer places a platform secret is even partially visible the better.
create or replace view included_providers
  with (security_invoker = true)
as
  select provider
  from platform_keys
  where enabled;

-- The view is `security_invoker`, so it would inherit the caller's (nil)
-- access to `platform_keys` and return nothing. Providers on offer are not a
-- secret, so this one reads as its definer — the *only* thing it exposes is a
-- list of provider names, with no key material of any kind.
alter view included_providers set (security_invoker = false);

grant select on included_providers to authenticated;
