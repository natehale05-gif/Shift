-- Make the entitlement functions reachable over the API.
--
-- `0004` put `managed_spend_micros` and `within_ceiling` in the `shift` schema,
-- and `0007` re-created them there. Both are correct SQL, both are asserted by
-- `tests/rls_test.sql`, and **neither has ever been callable over HTTP**:
-- PostgREST exposes `public` and nothing else, so `POST /rest/v1/rpc/
-- within_ceiling` resolves to `public.within_ceiling`, which did not exist.
--
-- What that cost. `provider-proxy` asks that endpoint whether an account may
-- spend, and its `catch` — correctly — answers no when the check cannot run.
-- So every managed call was refused, with a 402 saying the member's plan did
-- not cover it, while the member's plan covered it perfectly. The client made
-- the same call for the spend figure with `allowFailure: true`, so the miss
-- came back as zero and "$0.00 of $25.00 used" was printed with the confidence
-- of a measurement it never took.
--
-- Wrappers rather than moving the functions, because the rule they were
-- written under still holds: one definition of "entitled", not a second one
-- that can drift from it. `shift` keeps the logic; `public` gets a door.

-- What a member's own device asks: how much have I spent this month.
--
-- No argument, deliberately. The account comes from the caller's own token, so
-- there is no version of this call that asks about somebody else — which is
-- what makes it safe to hand to `authenticated`.
create or replace function public.managed_spend_micros()
returns bigint
language sql
stable
security invoker
set search_path = ''
as $$
  select shift.managed_spend_micros(shift.current_user_id())
$$;

-- What the proxy asks, holding the service role: may *this* account spend.
--
-- It has to name an account — the proxy authenticates the member at the
-- gateway and then talks to PostgREST as the service role, so there is no JWT
-- for `current_user_id()` to read. That is exactly why the grant below is
-- `service_role` alone: an account-taking entitlement check that
-- `authenticated` could call is a way to ask questions about other people.
create or replace function public.within_ceiling(account uuid)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select shift.within_ceiling(account)
$$;

-- Revoked before granted, and not as ceremony.
--
-- Supabase's default privileges grant EXECUTE on every new `public` function to
-- `anon` and `authenticated`. That is the same host behaviour `0006` exists to
-- undo for tables, and without these lines `anon` could ask whether any account
-- id it can guess is entitled to spend.
revoke all on function public.managed_spend_micros()
  from public, anon, authenticated, service_role;
revoke all on function public.within_ceiling(uuid)
  from public, anon, authenticated, service_role;

grant execute on function public.managed_spend_micros()
  to authenticated, service_role;
grant execute on function public.within_ceiling(uuid) to service_role;
