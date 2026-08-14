-- Replace the `security definer` view with the two-layer pattern the rest of
-- this schema already uses.
--
-- `0008` made `included_providers` run as its definer so it could see through
-- `platform_keys`' deny-everything row security. The host's linter flags that
-- as an ERROR, and it is right to: a definer view is a standing invitation for
-- the next person to add a column and leak it with the creator's rights. The
-- view is safe *today* only because of what it happens to select.
--
-- The honest question is what a signed-in member may know. "Anthropic is one
-- of the providers your plan covers" is a product fact — it belongs on the
-- pricing page. `last_four`, `kms_key_id` and the ciphertext are not, and
-- never become so.
--
-- So: a row policy for the rows (enabled ones), a column grant for the columns
-- (the provider name), and an ordinary invoker view on top. Exactly how
-- `provider_keys` is handled, which also means one pattern to audit instead of
-- two.

drop view if exists included_providers;

drop policy if exists platform_keys_names_visible on platform_keys;
create policy platform_keys_names_visible on platform_keys
  for select using (enabled);

-- The policy alone would expose every column of an enabled row. This is the
-- half that keeps the secret secret.
grant select (provider) on platform_keys to authenticated;

create or replace view included_providers
  with (security_invoker = true)
as
  select provider from platform_keys;

grant select on included_providers to authenticated;
