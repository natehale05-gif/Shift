# The SHIFT AI backend

Postgres schema, row security, and (later) the edge functions behind the
membership, connectors, scheduled tasks and server-side workspaces.

**Supabase is the first host, not an assumption.** The whole point of the
layout below is that moving to Neon, RDS, Fly, or a self-hosted Postgres is a
configuration change and a data migration — not a rewrite.

## Portability, and how it is enforced

| Piece | Choice | Why it moves |
|---|---|---|
| Schema | plain SQL migrations, no Supabase-only DDL | `pg_dump` restores into any Postgres |
| Identity | `shift.current_user_id()`, reading PostgREST's `request.jwt.claims` | any issuer that mints a `sub` claim works |
| Row security | standard Postgres RLS + column privileges | Postgres features, not Supabase ones |
| Roles | `anon` / `authenticated` / `service_role`, created by `0001` if missing | the names Supabase uses, but ours to create |

Two things are deliberately **absent**, and their absence is the portability
contract: nothing references `auth.users`, and nothing calls `auth.uid()`.
Those are the two hooks that would weld this to one vendor.

`tool/test_migrations.sh` is what keeps it honest. It applies every migration to
a **plain** PostgreSQL — never a Supabase image — and then runs the row-security
assertions against it. Anything Supabase-only that creeps in fails there, rather
than at the point somebody tries to move.

```sh
PGHOST=127.0.0.1 PGPORT=5433 PGUSER=postgres tool/test_migrations.sh
```

It checks four things: the migrations apply, applying them twice is a no-op, the
policies do what `tests/rls_test.sql` says, and **every** table forces row
security — that last one so a table added later without a policy fails loudly
instead of being world-readable and passing every test that does not know to
look for it.

## Migrations

| File | Contents |
|---|---|
| `0001_roles_and_identity.sql` | the three roles, the `shift` schema, `current_user_id()` |
| `0002_profiles.sql` | one row per account, keyed by the JWT subject |
| `0003_provider_keys.sql` | the key vault — ciphertext, and the privilege that stops a client reading it |
| `0004_subscriptions_and_usage.sql` | membership, the usage meter, and the spend ceiling |
| `0005_connections_tasks_workspaces.sql` | the tables G4–G6 need, with their policies already on |
| `0006_lock_down_grants.sql` | revokes the host's default grants and re-states exactly what each role may do |
| `0007_pin_function_search_path.sql` | every function pinned to `search_path = ''` |
| `0008_platform_keys.sql` | SHIFT's own keys — no owner, no policy, plus `profiles.is_admin` |
| `0009_included_providers_without_definer.sql` | which providers a plan covers, as an invoker view |
| `0010_profiles_self_provision.sql` | the insert that creates an account's own profile row |

Apply in filename order. They are idempotent, so a partial failure can be
re-run.

## Two rules that are not negotiable

**A secret is never readable by a client.** Row security filters rows, not
columns, so `provider_keys.ciphertext` and `connections.*_ciphertext` are
protected by column privileges instead: `authenticated` is granted `select` on
the metadata columns only. Clients read `provider_key_metadata` — provider, last
four, when it was added. Decryption happens inside an edge function holding the
service role and a KMS key, and the plaintext is never returned, never logged.

**A client cannot write anything that decides what it is owed.** `subscriptions`
and `usage_events` are read-only to `authenticated`: a client that could write
its own subscription could grant itself a membership, and one that could write
its own usage could make the meter measure nothing. Both are written by the
server. `scheduled_tasks` is the one table a member owns outright, and its
policy carries `with check` so a row cannot be written under someone else's id.

## SHIFT's own keys, and who may add one

`platform_keys` holds the keys a membership buys — one row per provider, owned
by nobody. It has **row security on and no policy at all**, which denies every
client role outright: the only way in or out is an edge function holding the
service role. A leak in `provider_keys` is one member's bill; a leak here is
every member's.

A signed-in member may know one thing about them: which providers their plan
covers, through the `included_providers` view (a row policy for the enabled
rows, a column grant for the provider name, and an ordinary invoker view on
top — the same two-layer pattern as everywhere else).

Adding or rotating one goes through `provider-key` with `scope: "platform"`,
which checks `profiles.is_admin` **server-side with the service role** rather
than trusting a token claim. That column is not in the set `authenticated` may
insert or update, so an account cannot promote itself and then post a key. The
Settings card that offers the form is hidden from everyone else, but that is
presentation: the endpoint returns a bare `403` regardless of who found it.

There is no way to grant admin from inside the app, deliberately. The first one
is set directly against the database:

```sql
update profiles set is_admin = true where email = 'you@example.com';
```

## Profiles are created by the client

`0010` grants `authenticated` an insert on `profiles (id, email, display_name)`
behind a policy checking `id = shift.current_user_id()`, and the client posts
that row after every sign-in.

The obvious alternative is a trigger on `auth.users` — and it is exactly what
the portability contract above forbids, since it would name the vendor's auth
schema and could not be run by `tool/test_migrations.sh` at all. A migration
the portability test cannot run is one that stops being portable without anyone
noticing.

The insert cannot create somebody else's row (the policy reads the id from the
token, not from the request) and cannot create an admin (`is_admin` is not in
the column grant). Both are asserted in `tests/rls_test.sql`.

## Secrets

Nothing secret belongs in this repository or in a chat message. `.env.example`
lists **names only**.

- The Supabase project URL and anon key are public by design and ship in the
  client.
- The **service-role key**, the **KMS key id**, and the **Stripe keys** go into
  GitHub Actions secrets and the Supabase dashboard directly.
- Anything pasted into a conversation is treated as compromised and rotated.

## Edge functions

`functions/` holds them, and they are **plain HTTP handlers** —
`(Request, context) => Response`, written against WebCrypto and nothing else.
No handler imports a Supabase library; `_shared/handler.js` is the only file
that knows where it is running, so the bodies move to Node, Bun or Workers by
swapping that one adapter. It is also what makes them testable with no platform
at all:

```sh
node --test supabase/functions/tests/*.test.js
```

| Function | What it does |
|---|---|
| `provider-key` | the encrypting front door to the vault — the only way a secret gets in, for a member's own key or, with `scope: "platform"` and an admin, for SHIFT's |
| `stripe-webhook` | the only writer of `subscriptions` — entitlement comes from Stripe or from nowhere |

`stripe-webhook` is deliberately **unauthenticated**: Stripe has no JWT, so the
signature *is* the authentication. That is why verification is the first thing
it does and why a bad signature returns 400 without touching the database — an
endpoint that skips it is a public URL anyone can POST "this account is now a
paying member" to.

**The master key is an environment variable, not a hosted KMS.** The *shape* is
a KMS's — a master that never leaves the server, a fresh IV per record, and a
`kms_key_id` column recording which master encrypted what so a rotation can find
its work — but moving to real KMS means replacing `masterKeyBytes()` and nothing
else. The stored record format does not change. Said plainly here rather than
implied by the column name.

## What is not here yet

The billing portal (creating a Checkout session), the scheduled-task runner,
the metered proxy that spends managed keys, and the client wiring. Each needs a live project or real Stripe keys to verify against,
which is the next thing to set up.
