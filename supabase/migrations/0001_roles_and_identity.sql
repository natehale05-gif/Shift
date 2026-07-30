-- Roles and the one function every policy is written against.
--
-- Supabase creates `anon`, `authenticated` and `service_role` for you; a plain
-- Postgres does not. Creating them here costs nothing on Supabase (they already
-- exist) and is what lets the same SQL restore into Neon, RDS or a container.
--
-- Nothing in this schema references `auth.users` or calls `auth.uid()`. Those
-- are the two things that would weld it to one host.

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

create schema if not exists shift;
grant usage on schema shift to anon, authenticated, service_role;

create extension if not exists pgcrypto;

-- The signed-in account, read out of the request's JWT claims.
--
-- `request.jwt.claims` is PostgREST's GUC, not a Supabase invention — any host
-- running PostgREST sets it, and a different stack sets the same setting before
-- running a statement. That is the whole portability story for row security:
-- move the issuer, keep the claim.
--
-- Returns null when there is no usable token, which is what makes every policy
-- below deny by default rather than erroring.
--
-- "No usable token" covers more than "no token". The setting can be absent, the
-- empty string, valid JSON without a `sub`, or not JSON at all — and the last
-- two must *deny*, not raise. A parse error inside a row policy surfaces as a
-- 500 on an ordinary read, which reads as the service being broken rather than
-- as the request being unauthenticated. Written in plpgsql for exactly that
-- exception handler; the SQL version raised on an empty setting.
create or replace function shift.current_user_id() returns uuid
language plpgsql
stable
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

grant execute on function shift.current_user_id() to anon, authenticated, service_role;
