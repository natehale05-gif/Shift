-- Nothing was creating a profile row.
--
-- `0002` says rows are "created by the server on first sign-in, never by a
-- client" — and then no server code creates one. So an account could sign up
-- successfully and have no profile at all: no display name, no `is_admin`, and
-- `0008`'s admin check reading a row that does not exist. The account works,
-- but everything hanging off the profile silently does not.
--
-- The obvious fix on this host is a trigger on `auth.users`. That is exactly
-- what `0001` and `0002` refuse to do: nothing in this schema names the auth
-- tables, because that is what lets the identity provider be replaced without
-- a migration. A trigger would also be unrunnable in `tool/test_migrations.sh`,
-- which applies these files to a plain PostgreSQL with no `auth` schema at all
-- — and a migration the portability test cannot run is a migration that stops
-- being portable without anyone noticing.
--
-- So the client creates its own row, and the database makes it impossible to
-- create anyone else's.

drop policy if exists profiles_insert_own on profiles;
create policy profiles_insert_own on profiles
  for insert with check (id = shift.current_user_id());

-- Two layers, same pattern as everywhere else in this schema: the policy says
-- *which row* (yours, keyed on the token subject — a client cannot name
-- another id, because the check reads the id from the token rather than from
-- the request), and the column list says *which columns*. `is_admin` is not in
-- it, so the insert that provisions an account cannot also promote it. Neither
-- half is sufficient alone.
grant insert (id, email, display_name) on profiles to authenticated;
