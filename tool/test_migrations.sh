#!/usr/bin/env bash
# Applies every migration to a *plain* PostgreSQL and runs the row-security
# assertions against it.
#
# Plain on purpose. The schema is meant to restore into Neon, RDS or a
# self-hosted Postgres, so the test that guards that is simply: never run it on
# a Supabase image. Anything Supabase-only that creeps in — `auth.uid()`, a
# reference to `auth.users`, an extension only they ship — fails here rather
# than at the point somebody tries to move hosts.
#
#   PGHOST=127.0.0.1 PGPORT=5433 PGUSER=postgres tool/test_migrations.sh
set -euo pipefail

HOST="${PGHOST:-127.0.0.1}"
PORT="${PGPORT:-5433}"
USER="${PGUSER:-postgres}"
DB="shift_migration_test_$$"

root="$(cd "$(dirname "$0")/.." && pwd)"

cleanup() {
  psql -h "$HOST" -p "$PORT" -U "$USER" -d postgres -q \
    -c "drop database if exists \"$DB\"" >/dev/null 2>&1 || true
}
trap cleanup EXIT

psql -h "$HOST" -p "$PORT" -U "$USER" -d postgres -q -c "create database \"$DB\""

# Reproduce the host's starting state before applying anything.
#
# This is not decoration. Supabase creates the three roles *and* ships
#
#   alter default privileges in schema public
#     grant all on tables to anon, authenticated, service_role;
#
# so every table a migration creates arrives with full privileges already
# granted to both client roles. Without this block the local database is more
# restrictive than production, and a migration that fails to revoke those grants
# passes here and ships a hole — which is exactly what happened: the
# column-level grant protecting `provider_keys.ciphertext` was silently
# overridden on the real project while every local assertion passed.
#
# The rule this encodes: a test environment that is *safer* than production
# tests nothing.
psql -h "$HOST" -p "$PORT" -U "$USER" -d "$DB" -q -v ON_ERROR_STOP=1 <<'SQL'
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin noinherit bypassrls;
  end if;
end
$$;
grant usage on schema public to anon, authenticated, service_role;
alter default privileges in schema public
  grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public
  grant all on sequences to anon, authenticated, service_role;
SQL

for migration in "$root"/supabase/migrations/*.sql; do
  echo "applying $(basename "$migration")"
  psql -h "$HOST" -p "$PORT" -U "$USER" -d "$DB" -q -v ON_ERROR_STOP=1 \
    -f "$migration"
done

# Applying twice must be a no-op. A migration that only works on an empty
# database is one that cannot be re-run after a partial failure.
for migration in "$root"/supabase/migrations/*.sql; do
  psql -h "$HOST" -p "$PORT" -U "$USER" -d "$DB" -q -v ON_ERROR_STOP=1 \
    -f "$migration" >/dev/null
done
echo "migrations are idempotent"

psql -h "$HOST" -p "$PORT" -U "$USER" -d "$DB" -q -v ON_ERROR_STOP=1 \
  -f "$root/supabase/tests/rls_test.sql"

# Every table must have row security forced on. A new table added without it
# would be readable by every account, and it would pass every test above
# because no test knows to look for it.
missing=$(psql -h "$HOST" -p "$PORT" -U "$USER" -d "$DB" -tAc "
  select string_agg(relname, ', ')
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind = 'r'
    and not (c.relrowsecurity and c.relforcerowsecurity)")

if [ -n "$missing" ]; then
  echo "FAIL: tables without forced row security: $missing" >&2
  exit 1
fi
echo "every table forces row security"

# The privilege surface, asserted as a whole rather than one column at a time.
#
# Row security is the first layer and these grants are the second, and the
# second is the one that can be switched off from outside the file that
# declares it. Naming every privilege a client role is allowed to hold means a
# grant that reappears — from a host default, or from a later migration
# forgetting to revoke — fails here instead of shipping.
unexpected=$(psql -h "$HOST" -p "$PORT" -U "$USER" -d "$DB" -tAc "
  select string_agg(format('%s:%s:%s', grantee, table_name, privilege_type), ', ')
  from information_schema.role_table_grants
  where table_schema = 'public'
    and grantee in ('anon', 'authenticated')
    and (grantee, table_name, privilege_type) not in (
      ('authenticated', 'profiles', 'SELECT'),
      ('authenticated', 'profiles', 'UPDATE'),
      ('authenticated', 'provider_keys', 'SELECT'),
      ('authenticated', 'provider_keys', 'DELETE'),
      ('authenticated', 'provider_key_metadata', 'SELECT'),
      ('authenticated', 'subscriptions', 'SELECT'),
      ('authenticated', 'usage_events', 'SELECT'),
      ('authenticated', 'connections', 'SELECT'),
      ('authenticated', 'connections', 'DELETE'),
      ('authenticated', 'scheduled_tasks', 'SELECT'),
      ('authenticated', 'scheduled_tasks', 'INSERT'),
      ('authenticated', 'scheduled_tasks', 'UPDATE'),
      ('authenticated', 'scheduled_tasks', 'DELETE'),
      ('authenticated', 'workspaces', 'SELECT'),
      ('authenticated', 'workspaces', 'DELETE')
    )")

if [ -n "$unexpected" ]; then
  echo "FAIL: privileges a client role should not hold: $unexpected" >&2
  exit 1
fi
echo "client roles hold only their intended privileges"

# `provider_keys` and `connections` appear above with table-wide SELECT because
# information_schema reports a column grant that way. What matters is which
# columns, so check those directly — this is the assertion the host's default
# privileges defeated.
secret=$(psql -h "$HOST" -p "$PORT" -U "$USER" -d "$DB" -tAc "
  select string_agg(format('%s.%s', table_name, column_name), ', ')
  from information_schema.column_privileges
  where table_schema = 'public'
    and grantee in ('anon', 'authenticated')
    and column_name in ('ciphertext', 'access_ciphertext', 'refresh_ciphertext')")

if [ -n "$secret" ]; then
  echo "FAIL: a client role can read a secret column: $secret" >&2
  exit 1
fi
echo "no client role can read a ciphertext column"
