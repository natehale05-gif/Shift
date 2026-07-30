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
