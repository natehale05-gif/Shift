-- Row security, asserted rather than assumed.
--
-- Run against a *plain* PostgreSQL (see tool/test_migrations.sh), which makes
-- this two tests at once: that one account cannot read another's rows, and that
-- the schema carries nothing Supabase-only. If it stops passing on stock
-- Postgres, something has welded the database to one host.
--
-- Every assertion is an ASSERT rather than an expected-output comparison, so a
-- failure names the rule that broke instead of printing a diff.

\set ON_ERROR_STOP on

begin;

-- Two accounts and one row each, written as the service role would.
insert into profiles (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@test'),
  ('22222222-2222-2222-2222-222222222222', 'b@test');

insert into provider_keys
  (owner_id, provider, key_owner, ciphertext, kms_key_id, last_four)
values
  ('11111111-1111-1111-1111-111111111111', 'anthropic', 'user',
   '\x00'::bytea, 'kms-1', '1234'),
  ('22222222-2222-2222-2222-222222222222', 'anthropic', 'user',
   '\x00'::bytea, 'kms-1', '5678');

insert into subscriptions (owner_id, status, plan, spend_ceiling_micros) values
  ('11111111-1111-1111-1111-111111111111', 'active', 'pro', 10000000),
  ('22222222-2222-2222-2222-222222222222', 'none', null, 0);

insert into usage_events (owner_id, provider, key_owner, cost_micros) values
  ('11111111-1111-1111-1111-111111111111', 'anthropic', 'managed', 2500000),
  ('22222222-2222-2222-2222-222222222222', 'anthropic', 'managed', 9000000);

insert into scheduled_tasks (owner_id, name, cron, prompt) values
  ('11111111-1111-1111-1111-111111111111', 'Morning brief', '0 8 * * *', 'brief me');

-- ---------------------------------------------------------------- account A
set local role authenticated;
set local request.jwt.claims =
  '{"sub":"11111111-1111-1111-1111-111111111111"}';

do $$
begin
  assert (select count(*) from profiles) = 1,
    'a member sees exactly one profile — their own';
  assert (select id from profiles) = '11111111-1111-1111-1111-111111111111',
    'and it is theirs';

  assert (select count(*) from provider_key_metadata) = 1,
    'key metadata is filtered to the owner';
  assert (select last_four from provider_key_metadata) = '1234',
    'and it is the owner''s key';

  assert (select count(*) from scheduled_tasks) = 1,
    'scheduled tasks are filtered to the owner';

  assert shift.managed_spend_micros(
      '11111111-1111-1111-1111-111111111111') = 2500000,
    'managed spend counts only this account';
  assert shift.within_ceiling('11111111-1111-1111-1111-111111111111'),
    'an active member under their ceiling may spend';
end
$$;

-- The secret itself is unreadable even to its own owner: only an edge function
-- holding the service role can decrypt a key, and this is the privilege that
-- makes that true rather than merely intended.
do $$
begin
  begin
    perform ciphertext from provider_keys;
    raise exception 'ciphertext was readable by a client';
  exception
    when insufficient_privilege then null;  -- expected
  end;
end
$$;

-- A member may write their own schedule…
insert into scheduled_tasks (owner_id, name, cron, prompt)
values ('11111111-1111-1111-1111-111111111111', 'Evening', '0 20 * * *', 'x');

-- …and may not write one for anybody else.
do $$
begin
  begin
    insert into scheduled_tasks (owner_id, name, cron, prompt)
    values ('22222222-2222-2222-2222-222222222222', 'Theirs', '0 9 * * *', 'x');
    raise exception 'a task was inserted for another account';
  exception
    when insufficient_privilege then null;  -- WITH CHECK rejected it
  end;
end
$$;

-- Provisioning a profile is the one insert a client makes, so it gets the same
-- scrutiny as the writes it must not make. Somebody else's row first…
do $$
begin
  begin
    insert into profiles (id, email)
    values ('22222222-2222-2222-2222-222222222222', 'stolen@test');
    raise exception 'a profile was created for another account';
  exception
    when insufficient_privilege then null;  -- WITH CHECK rejected it
    when unique_violation then
      raise exception 'the row existed, so the policy was never tested';
  end;
end
$$;

-- …then their own, but as an admin. This is the one that matters: creating
-- your own profile is allowed, and it is the only moment a client chooses what
-- goes in the row.
do $$
begin
  begin
    insert into profiles (id, email, is_admin)
    values ('11111111-1111-1111-1111-111111111111', 'a@test', true);
    raise exception 'a client inserted is_admin';
  exception
    when insufficient_privilege then null;  -- no INSERT grant on that column
    when unique_violation then
      raise exception 'the column grant was never reached';
  end;
end
$$;

-- Granting yourself a membership is not a thing a client can do.
do $$
begin
  begin
    update subscriptions set status = 'active', spend_ceiling_micros = 999999999
    where owner_id = '11111111-1111-1111-1111-111111111111';
    raise exception 'a client updated its own subscription';
  exception
    when insufficient_privilege then null;  -- no UPDATE grant
  end;
end
$$;

-- Nor is writing its own usage, which would make the meter meaningless.
do $$
begin
  begin
    insert into usage_events (owner_id, provider, key_owner, cost_micros)
    values ('11111111-1111-1111-1111-111111111111', 'anthropic', 'managed', 0);
    raise exception 'a client wrote a usage event';
  exception
    when insufficient_privilege then null;
  end;
end
$$;

-- ---------------------------------------------------------------- account B
set local request.jwt.claims =
  '{"sub":"22222222-2222-2222-2222-222222222222"}';

do $$
begin
  assert (select count(*) from profiles) = 1,
    'the second account sees only itself';
  assert (select id from profiles) = '22222222-2222-2222-2222-222222222222',
    'and not the first';
  assert (select last_four from provider_key_metadata) = '5678',
    'keys did not leak across accounts';
  assert (select count(*) from scheduled_tasks) = 0,
    'and neither did the first account''s tasks';
  assert not shift.within_ceiling('22222222-2222-2222-2222-222222222222'),
    'no membership means no managed spend';
end
$$;

-- ---------------------------------------------------------------- account C
-- A brand-new account, which is the state every account starts in: signed up,
-- no profile row, nothing on the server yet. Nothing else creates one — no
-- trigger, no server job — so if this insert did not work, an account would
-- exist with no profile and `is_admin` would have nowhere to be read from.
set local request.jwt.claims =
  '{"sub":"33333333-3333-3333-3333-333333333333"}';

insert into profiles (id, email) values
  ('33333333-3333-3333-3333-333333333333', 'c@test');

do $$
begin
  assert (select count(*) from profiles) = 1,
    'a new account can create its own profile';
  assert (select id from profiles) = '33333333-3333-3333-3333-333333333333',
    'and it is theirs';
  assert not (select is_admin from profiles),
    'and it is not an admin — that column is not theirs to set';
end
$$;

-- -------------------------------------------------------------- no token
-- Two separate defences, and it is worth knowing which one is holding.
--
-- `anon` has no grant at all, so it is stopped before row security is even
-- consulted. A test asserting "anon reads zero rows" would pass whether or not
-- the policies were right, so assert the privilege error instead.
reset role;
set local role anon;
set local request.jwt.claims = '';

do $$
begin
  begin
    perform count(*) from profiles;
    raise exception 'anon could read profiles at all';
  exception
    when insufficient_privilege then null;  -- expected
  end;

  -- `0011` put a wrapper for this in `public` so PostgREST can reach it, and
  -- the wrapper takes the account to ask about — which is the whole reason the
  -- grant is `service_role` alone. Reachable by a client, it would answer
  -- questions about other people's accounts. Supabase grants EXECUTE on new
  -- public functions to both client roles by default, so this asserts the
  -- revoke rather than assuming it.
  begin
    perform public.within_ceiling('11111111-1111-1111-1111-111111111111');
    raise exception 'anon could ask whether another account may spend';
  exception
    when insufficient_privilege then null;  -- expected
  end;
end
$$;

-- The case row security actually has to catch: the `authenticated` role with a
-- token that names nobody. current_user_id() is null, `owner_id = null` is
-- null, null is not true, so no row matches.
reset role;
set local role authenticated;
set local request.jwt.claims = '';

do $$
begin
  assert shift.current_user_id() is null, 'an empty token is nobody';
  assert (select count(*) from profiles) = 0, 'and reads nothing';
  assert (select count(*) from provider_key_metadata) = 0, 'no key metadata';
  assert (select count(*) from scheduled_tasks) = 0, 'no schedules';
end
$$;

-- A malformed or subject-less token denies rather than raising. A JSON parse
-- error inside a policy would surface as a 500 on an ordinary read, which looks
-- like the service is down instead of like the caller is not signed in.
set local request.jwt.claims = 'not json at all';
do $$
begin
  assert shift.current_user_id() is null, 'a malformed token is nobody';
  assert (select count(*) from profiles) = 0, 'and reads nothing';
end
$$;

set local request.jwt.claims = '{"role":"authenticated"}';
do $$
begin
  assert shift.current_user_id() is null, 'a token with no subject is nobody';
  assert (select count(*) from profiles) = 0, 'and reads nothing';
end
$$;

rollback;

\echo 'RLS: all assertions passed'
