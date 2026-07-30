-- One row per account.
--
-- `id` is the JWT subject, not a foreign key into an auth table. That is
-- deliberate: it means the identity provider can be replaced without a schema
-- migration, and it is why nothing here references `auth.users`.
create table if not exists profiles (
  id           uuid primary key,
  email        text,
  display_name text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

alter table profiles enable row level security;
-- FORCE so the table owner is not silently exempt. Without it a migration or a
-- job connecting as the owner reads every row, and the policies below are
-- decoration.
alter table profiles force row level security;

drop policy if exists profiles_select_own on profiles;
create policy profiles_select_own on profiles
  for select using (id = shift.current_user_id());

drop policy if exists profiles_update_own on profiles;
create policy profiles_update_own on profiles
  for update using (id = shift.current_user_id())
  with check (id = shift.current_user_id());

-- Rows are created by the server on first sign-in, never by a client: a client
-- that could insert could insert someone else's id.
grant select, update on profiles to authenticated;
grant all on profiles to service_role;
