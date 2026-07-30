-- Pin every function's `search_path`.
--
-- Found by the host's security linter after the schema went up, and it is a
-- real hole rather than a style note. Without a pinned `search_path`, the
-- schemas a function resolves names in are chosen by whoever calls it. A
-- caller who can create a schema and put their own `subscriptions` table in it
-- can then make `within_ceiling()` read that instead — and `within_ceiling` is
-- the function that decides whether an account may spend SHIFT's money.
--
-- `current_user_id()` matters most of all: it is named in every row-security
-- policy in the database, so anything that changes what it returns changes who
-- can read what, everywhere at once.
--
-- `search_path = ''` rather than `= public`: with an empty path *nothing*
-- resolves implicitly, so every reference below has to be schema-qualified and
-- a future edit that forgets to qualify fails immediately instead of quietly
-- resolving somewhere unintended. Built-ins keep working because `pg_catalog`
-- is always searched first regardless.

create or replace function shift.current_user_id() returns uuid
language plpgsql
stable
set search_path = ''
as $$
declare
  claims text := current_setting('request.jwt.claims', true);
begin
  if claims is null or claims = '' then
    return null;
  end if;
  return nullif(claims::json ->> 'sub', '')::uuid;
exception
  when others then
    return null;
end
$$;

create or replace function shift.managed_spend_micros(account uuid)
returns bigint
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(sum(cost_micros), 0)::bigint
  from public.usage_events
  where owner_id = account
    and key_owner = 'managed'
    and occurred_at >= date_trunc('month', now())
$$;

create or replace function shift.within_ceiling(account uuid)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select exists (
    select 1 from public.subscriptions s
    where s.owner_id = account
      and s.status in ('trialing', 'active')
      and shift.managed_spend_micros(account) < s.spend_ceiling_micros
  )
$$;

grant execute on function shift.current_user_id() to anon, authenticated, service_role;
grant execute on function shift.managed_spend_micros(uuid) to authenticated, service_role;
grant execute on function shift.within_ceiling(uuid) to authenticated, service_role;
