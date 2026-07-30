-- Membership, and the meter that stops it costing more than it earns.

create table if not exists subscriptions (
  owner_id               uuid primary key references profiles(id) on delete cascade,
  -- 'none' is a real state, not a missing row: it is what someone using their
  -- own keys has, and the app must work for them.
  status                 text not null default 'none'
                           check (status in ('none', 'trialing', 'active',
                                             'past_due', 'canceled')),
  plan                   text,
  stripe_customer_id     text unique,
  stripe_subscription_id text unique,
  current_period_end     timestamptz,
  -- The hard ceiling on managed-key spend for one billing period, in
  -- millionths of a dollar. Ships with the membership rather than after it: a
  -- plan that spends SHIFT's keys with no ceiling is an unbounded bill.
  spend_ceiling_micros   bigint not null default 0
                           check (spend_ceiling_micros >= 0),
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now()
);

alter table subscriptions enable row level security;
alter table subscriptions force row level security;

-- Read-only to the member. Status changes come from the Stripe webhook, which
-- runs as the service role; a client that could write this could grant itself
-- a membership.
drop policy if exists subscriptions_select_own on subscriptions;
create policy subscriptions_select_own on subscriptions
  for select using (owner_id = shift.current_user_id());

grant select on subscriptions to authenticated;
grant all on subscriptions to service_role;

-- One row per billable call. Append-only: a member may read their own usage and
-- may never write it, or the meter measures nothing.
create table if not exists usage_events (
  id            bigserial primary key,
  owner_id      uuid not null references profiles(id) on delete cascade,
  occurred_at   timestamptz not null default now(),
  provider      text not null,
  model         text,
  -- Which key paid: 'managed' spend counts against the ceiling, 'user' spend
  -- is the member's own bill and is recorded only so they can see it.
  key_owner     text not null check (key_owner in ('user', 'managed')),
  input_tokens  integer not null default 0 check (input_tokens >= 0),
  output_tokens integer not null default 0 check (output_tokens >= 0),
  cost_micros   bigint not null default 0 check (cost_micros >= 0)
);

create index if not exists usage_events_owner_time_idx
  on usage_events (owner_id, occurred_at desc);

alter table usage_events enable row level security;
alter table usage_events force row level security;

drop policy if exists usage_events_select_own on usage_events;
create policy usage_events_select_own on usage_events
  for select using (owner_id = shift.current_user_id());

grant select on usage_events to authenticated;
grant all on usage_events to service_role;

-- Managed spend in the current billing period, which is what the ceiling is
-- checked against before a call is dispatched.
--
-- `security_invoker` again, so this cannot be used to read another account's
-- usage: the row policy above still applies to the caller.
create or replace function shift.managed_spend_micros(account uuid)
returns bigint
language sql
stable
security invoker
as $$
  select coalesce(sum(cost_micros), 0)::bigint
  from usage_events
  where owner_id = account
    and key_owner = 'managed'
    and occurred_at >= date_trunc('month', now())
$$;

grant execute on function shift.managed_spend_micros(uuid)
  to authenticated, service_role;

-- Whether one more managed call is allowed. A subscription that is not active,
-- or a missing row, means no — the safe answer when the record is incomplete
-- is not to spend.
create or replace function shift.within_ceiling(account uuid)
returns boolean
language sql
stable
security invoker
as $$
  select exists (
    select 1 from subscriptions s
    where s.owner_id = account
      and s.status in ('trialing', 'active')
      and shift.managed_spend_micros(account) < s.spend_ceiling_micros
  )
$$;

grant execute on function shift.within_ceiling(uuid) to authenticated, service_role;
