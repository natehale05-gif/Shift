-- The three tables G4–G6 need. Created now, with their policies, because
-- adding a table to a live database is easy and adding row security to one that
-- already holds other people's data is not.

-- OAuth connections to outside services (Gmail, Drive, …).
--
-- Tokens are encrypted like provider keys and, like them, are never returned to
-- a client: refresh happens server-side. Same column-privilege trick, for the
-- same reason.
create table if not exists connections (
  id                uuid primary key default gen_random_uuid(),
  owner_id          uuid not null references profiles(id) on delete cascade,
  service           text not null,
  external_account  text,
  access_ciphertext  bytea not null,
  refresh_ciphertext bytea,
  kms_key_id        text not null,
  scopes            text[] not null default '{}',
  expires_at        timestamptz,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  unique (owner_id, service, external_account)
);

create index if not exists connections_owner_idx on connections (owner_id);

alter table connections enable row level security;
alter table connections force row level security;

drop policy if exists connections_select_own on connections;
create policy connections_select_own on connections
  for select using (owner_id = shift.current_user_id());

drop policy if exists connections_delete_own on connections;
create policy connections_delete_own on connections
  for delete using (owner_id = shift.current_user_id());

grant select (id, owner_id, service, external_account, scopes, expires_at,
              created_at, updated_at)
  on connections to authenticated;
grant delete on connections to authenticated;
grant all on connections to service_role;

-- Turns to run on a schedule.
--
-- `cron` is stored as text and fired by one job that reads this table, rather
-- than by creating a `pg_cron` entry per task. That keeps the schedule as data:
-- moving to a host without `pg_cron` is then a matter of pointing any cron at
-- one endpoint, not of recreating hundreds of database jobs.
create table if not exists scheduled_tasks (
  id           uuid primary key default gen_random_uuid(),
  owner_id     uuid not null references profiles(id) on delete cascade,
  name         text not null,
  cron         text not null,
  prompt       text not null,
  enabled      boolean not null default true,
  last_run_at  timestamptz,
  next_run_at  timestamptz,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create index if not exists scheduled_tasks_due_idx
  on scheduled_tasks (next_run_at) where enabled;

alter table scheduled_tasks enable row level security;
alter table scheduled_tasks force row level security;

-- The one table a client owns outright: the member writes their own schedules.
-- WITH CHECK on insert and update is what stops an account writing a row that
-- belongs to somebody else.
drop policy if exists scheduled_tasks_all_own on scheduled_tasks;
create policy scheduled_tasks_all_own on scheduled_tasks
  for all using (owner_id = shift.current_user_id())
  with check (owner_id = shift.current_user_id());

grant select, insert, update, delete on scheduled_tasks to authenticated;
grant all on scheduled_tasks to service_role;

-- A sandboxed checkout the agentic coding loop works in.
create table if not exists workspaces (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid not null references profiles(id) on delete cascade,
  project_id    text,
  repo_url      text,
  branch        text,
  container_ref text,
  status        text not null default 'idle'
                  check (status in ('idle', 'starting', 'ready', 'stopped',
                                    'failed')),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index if not exists workspaces_owner_idx on workspaces (owner_id);

alter table workspaces enable row level security;
alter table workspaces force row level security;

drop policy if exists workspaces_select_own on workspaces;
create policy workspaces_select_own on workspaces
  for select using (owner_id = shift.current_user_id());

drop policy if exists workspaces_delete_own on workspaces;
create policy workspaces_delete_own on workspaces
  for delete using (owner_id = shift.current_user_id());

-- Creating one starts a container, which is the server's job, not a client's.
grant select, delete on workspaces to authenticated;
grant all on workspaces to service_role;
