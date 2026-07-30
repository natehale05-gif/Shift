-- Take back the blanket privileges the host hands out, and re-grant only what
-- each role actually needs.
--
-- **Found by running the schema against the real project, not locally.**
-- Supabase ships
--
--   alter default privileges in schema public
--     grant all on tables to anon, authenticated, service_role;
--
-- so every table created here arrived with `DELETE, INSERT, REFERENCES, SELECT,
-- TRIGGER, TRUNCATE, UPDATE` already granted to both client roles. That silently
-- overrode the column-level grant in `0003`: `provider_keys.ciphertext` — the
-- one column the whole vault exists to keep from clients — was readable by any
-- signed-in caller for their own row. The live assertion caught it; the local
-- one could not, because plain Postgres has no such default.
--
-- Row security was still doing its job throughout: no policy for insert or
-- update means those were denied regardless of the grant. But "RLS happens to
-- cover for it" is not the design. The column privilege is the second layer,
-- and a second layer that is quietly switched off is worse than none, because
-- the docs go on claiming it.
--
-- `revoke` then `grant` per table, rather than changing the schema's default
-- privileges: this file then says exactly what each role may do, and a reader
-- does not have to know what the host would otherwise have granted.

revoke all on all tables in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;

-- `anon` gets nothing. Signing in is what a client does first; there is no
-- table here an unauthenticated caller has business reading.

-- profiles — read and update your own; rows are created by the server.
grant select, update on profiles to authenticated;

-- provider_keys — see *that* a key exists, and delete it. Never the secret:
-- this is the grant the host's default was overriding.
grant select (id, owner_id, provider, key_owner, last_four, created_at, updated_at)
  on provider_keys to authenticated;
grant delete on provider_keys to authenticated;
grant select on provider_key_metadata to authenticated;

-- subscriptions — read only. A client that could write this could grant
-- itself a membership; the Stripe webhook is the only writer.
grant select on subscriptions to authenticated;

-- usage_events — read only. A client that could write this could make the
-- meter measure nothing.
grant select on usage_events to authenticated;

-- connections — same shape as provider_keys: metadata and delete, never the
-- tokens.
grant select (id, owner_id, service, external_account, scopes, expires_at,
              created_at, updated_at)
  on connections to authenticated;
grant delete on connections to authenticated;

-- scheduled_tasks — the one table a member owns outright.
grant select, insert, update, delete on scheduled_tasks to authenticated;
grant usage, select on all sequences in schema public to authenticated;

-- workspaces — read and delete; creating one starts a container, which is the
-- server's job.
grant select, delete on workspaces to authenticated;

-- Future tables must not re-inherit the blanket grant. This only governs
-- objects created by the role running it, which is the role migrations run as —
-- exactly the tables this schema will add later.
alter default privileges in schema public
  revoke all on tables from anon, authenticated;
alter default privileges in schema public
  revoke all on sequences from anon, authenticated;

-- service_role keeps everything: it is the edge functions, and it is the role
-- `bypassrls` exists for.
grant all on all tables in schema public to service_role;
grant all on all sequences in schema public to service_role;
