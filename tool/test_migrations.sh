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
      ('authenticated', 'profiles', 'INSERT'),
      ('authenticated', 'profiles', 'UPDATE'),
      ('authenticated', 'included_providers', 'SELECT'),
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

# Every function must pin its search_path.
#
# Without one, the schemas a function resolves names in are chosen by whoever
# calls it — and `shift.current_user_id()` is named in every row-security
# policy in the database, so changing what it returns changes who can read
# what, everywhere at once. The host's linter catches this after deployment;
# this catches it before.
unpinned=$(psql -h "$HOST" -p "$PORT" -U "$USER" -d "$DB" -tAc "
  select string_agg(p.proname, ', ')
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'shift'
    and not exists (
      select 1 from unnest(coalesce(p.proconfig, '{}')) as c
      where c like 'search_path=%')")

if [ -n "$unpinned" ]; then
  echo "FAIL: functions with a caller-controlled search_path: $unpinned" >&2
  exit 1
fi
echo "every function pins its search_path"

# The platform keys are the ones a leak would bill *every* member for, so the
# rule is the tightest in the schema: a client may learn which providers are
# included and nothing else — not the last four, not which key encrypted it,
# and obviously not the ciphertext.
exposed=$(psql -h "$HOST" -p "$PORT" -U "$USER" -d "$DB" -tAc "
  select string_agg(format('%s:%s', grantee, column_name), ', ')
  from information_schema.column_privileges
  where table_schema = 'public' and table_name = 'platform_keys'
    and grantee in ('anon', 'authenticated')
    and column_name <> 'provider'")

if [ -n "$exposed" ]; then
  echo "FAIL: a client can read platform key columns it should not: $exposed" >&2
  exit 1
fi

# And no write of any kind: adding or rotating one of SHIFT's keys goes
# through the edge function, which checks admin server-side.
writable=$(psql -h "$HOST" -p "$PORT" -U "$USER" -d "$DB" -tAc "
  select string_agg(distinct privilege_type, ', ')
  from information_schema.role_table_grants
  where table_schema = 'public' and table_name = 'platform_keys'
    and grantee in ('anon', 'authenticated')
    and privilege_type <> 'SELECT'")

if [ -n "$writable" ]; then
  echo "FAIL: a client can write platform_keys: $writable" >&2
  exit 1
fi
echo "platform_keys exposes provider names only, and is read-only to clients"

# No SECURITY DEFINER views. One added to see through row security is a
# standing invitation for the next column to leak with the creator rights.
definer=$(psql -h "$HOST" -p "$PORT" -U "$USER" -d "$DB" -tAc "
  select string_agg(c.relname, ', ')
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind = 'v'
    and not coalesce((
      select option_value = 'true' from pg_options_to_table(c.reloptions)
      where option_name = 'security_invoker'), false)")

if [ -n "$definer" ]; then
  echo "FAIL: views that run as their definer: $definer" >&2
  exit 1
fi
echo "no security-definer views"

# A member may rename themselves and must not be able to promote themselves.
promotable=$(psql -h "$HOST" -p "$PORT" -U "$USER" -d "$DB" -tAc "
  select string_agg(column_name, ', ')
  from information_schema.column_privileges
  where table_schema = 'public' and table_name = 'profiles'
    and grantee = 'authenticated' and privilege_type = 'UPDATE'
    and column_name <> 'display_name'")

if [ -n "$promotable" ]; then
  echo "FAIL: a member can update profiles columns they should not: $promotable" >&2
  exit 1
fi

# The same question for the insert that provisions the account. `0010` lets a
# client create its own profile row, which is the only way one gets created —
# so the row it creates must not be able to be an admin's, and must not be able
# to be somebody else's.
promotable_insert=$(psql -h "$HOST" -p "$PORT" -U "$USER" -d "$DB" -tAc "
  select string_agg(column_name, ', ')
  from information_schema.column_privileges
  where table_schema = 'public' and table_name = 'profiles'
    and grantee = 'authenticated' and privilege_type = 'INSERT'
    and column_name not in ('id', 'email', 'display_name')")

if [ -n "$promotable_insert" ]; then
  echo "FAIL: a member can insert profiles columns they should not: $promotable_insert" >&2
  exit 1
fi
echo "a member cannot promote themselves"
