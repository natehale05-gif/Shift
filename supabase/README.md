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

## Setting it up from a phone

Settings → **Server setup** (admin only) is where this happens. It shows live
state rather than a checklist to tick — a checklist that records what you told
it is one that lies — and it has a button for each thing the server can do:

- **Run test** sends one small request through the proxy and says what came
  back. This is the one that matters. A 404 (never deployed), a 402 (deployed
  and refusing), and a rejected key are three different faults with three
  different fixes, and from inside a chat all three look identical: a reply
  that never arrived.
- **Grant** gives an account a plan, which used to be an `insert into
  subscriptions` typed into a SQL editor.

The two settings no app can change — the Supabase Site URL, and the GitHub
credentials the deploy job needs — are one tap to the exact form, with the
value to paste already on the clipboard.

## Deploying the functions

Three are deployed and ACTIVE: `provider-key`, `provider-proxy`,
`admin-membership`.

**The two ways in, and which one to trust.**

`.github/workflows/backend.yml` deploys every function in `functions/` on a
push, after the migration assertions pass. That is the path that survives the
next edit: it ships the sources as they are, in the layout they are written in,
and nobody has to be available for it to happen.

The other way is the management API, one file at a time. It exists because the
workflow needs a credential a repository may not have yet, and being unable to
deploy at all is worse than deploying awkwardly — that gap is exactly how
`admin-membership` came to be missing while a button in Settings pointed at it.
`tool/bundle_function.py` is what makes it possible:

```sh
python3 tool/bundle_function.py provider-proxy --deno --lean
```

`--deno` appends the `Deno.serve` entrypoint; `--lean` drops whole-line
comments, halving `provider-proxy` from 32 KB to 16 KB, which matters when the
file has to travel as one literal string. `tests/bundle.test.js` imports every
bundle and drives a request through it — the bundler is on the deploy path now,
and a name collision between two inlined modules would otherwise surface as a
production 500 that no other test can see.

**It is the second-best path and this says so.** A file that reaches the server
by being copied can drift from its source, and one already has: `provider-key`'s
deployed copy was flattened by hand in an earlier session and its `handler.js`
no longer matches the one here. Nothing behaves differently — the drift is in
comments — but that is luck, not a property. The workflow overwrites all of it
from source, which is the actual fix.

Two settings turn the workflow on, and until they exist the step skips with a
message rather than failing (a missing credential means "this checkout cannot
deploy", not "this change is broken"):

| | Where | What |
|---|---|---|
| `SUPABASE_ACCESS_TOKEN` | repository **secret** | a personal access token from the Supabase dashboard |
| `SUPABASE_PROJECT_REF` | repository **variable** | the project ref from its URL |

`stripe-webhook` deploys with `--no-verify-jwt`, alone among them: Stripe has
no session to present, so its signature *is* its authentication and the handler
checks that first. Everything else keeps the gateway's JWT check in front of it.

## Secrets

Nothing secret belongs in this repository or in a chat message. `.env.example`
lists **names only**.

- The Supabase project URL and anon key are public by design and ship in the
  client — so they are **committed**, in `lib/backend/backend_config.dart`,
  rather than injected at build time. Injection was tried and failed in the
  worst way available: the repository variables were never set, every deploy
  compiled an empty URL, and the app shipped on `NoBackend` with its account
  section correctly and silently hidden. Sign-in was missing from the live site
  for a release and no check failed, because none existed. There is one now
  (`test/backend/backend_config_test.dart`), asserting both that a build has a
  backend and that the committed key is an `anon` token and not something with
  `bypassrls`. A `--dart-define` still overrides, which is how a staging or
  self-hosted project is pointed at.
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
| `provider-proxy` | spends SHIFT's keys for a member — the only reader of the vault |
| `admin-membership` | grants a plan, until payments can sell one |
| `stripe-webhook` | the only writer of `subscriptions` — entitlement comes from Stripe or from nowhere |

### The proxy

`provider-proxy` is what makes a membership worth anything. A member's device
sends the request body it would have sent to the provider, to us instead, with
its own session token; the credential is attached where the device cannot reach
it, the reply is streamed straight back, and the cost is written down.

```
POST /functions/v1/provider-proxy/<provider>/<the provider's own path>
```

Transparent passthrough on purpose. The clients' wire-format code — the part the
rebuild deliberately ported rather than rewrote — keeps working untouched, and
the server never becomes a second implementation of three protocols it would
then have to track as they drift.

Four things must hold at once, and each is a way to lose money or leak a key:

| | Where |
|---|---|
| the caller is signed in | the gateway, plus `subjectOf` |
| the caller is entitled and under budget | `shift.within_ceiling`, the same function `rls_test.sql` asserts |
| the destination is one **we** chose | `_shared/upstream.js` — fixed hosts, path allowlist |
| the call is metered even when the provider reports nothing | `_shared/usage_meter.js` + `UNREPORTED_CALL_MICROS` |

Three of those are ordinary care. The fourth is the one that is easy to get
backwards: a response shape the meter does not recognise must still cost
something, or "return something unparseable" becomes a way to spend SHIFT's
keys for free. For the same reason an unknown model is priced at the *most
expensive* rate in the table rather than at zero.

**The ceiling is a stop-line, not a hard cap.** Nobody knows what a call costs
until the reply ends, so entitlement is checked before dispatch and cost
recorded after. One call can overshoot by its own size. That is inherent, it is
bounded by a single request, and it beats buffering an entire reply so the cost
can be known first — which would turn a live conversation into a long wait.

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

The billing portal (creating a Checkout session) and the scheduled-task runner.
Both need real Stripe keys or a scheduler to verify against.

Until the billing portal exists, **nothing can make an account paid except an
admin pressing Grant** — a decision someone makes rather than a purchase
someone completes. That is the honest description of where membership stands.
