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
| `provider-key` | the encrypting front door to the vault — the only way a secret gets in |
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
