# SHIFT — handoff prompt

You are picking up work on SHIFT, a Flutter app (six modes: Chat/Voice, Code,
Visual, Design, Work, Notes) that resells API access on a subscription and also
supports bring-your-own-key.

Everything below is verified state, not description. Where a fact came from
reading a live system rather than the repository, it says so — because the two
have disagreed, and that disagreement is the whole subject of the top task.

---

## Ground truth

| | |
|---|---|
| Repo | `natehale05-gif/Shift`, working dir `/home/user/Shift` |
| Branch | `claude/shiftai-flutter-chat-app-rjtgyj` — **develop and push here only** |
| HEAD | `f4ba833` |
| Flutter | `/opt/flutter/bin/flutter` (3.44.x) |
| Suite | 867 tests green |
| Server | Supabase project `xmjaqizlrlsvjbwqmtdo` (us-east-2, Postgres 17) |
| Live app | https://natehale05-gif.github.io/Shift/ |

### The gate — run all of it before every commit

```
/opt/flutter/bin/flutter analyze          # exits non-zero on INFO-level lints
/opt/flutter/bin/flutter test
node --test supabase/functions/tests/*.test.js
python3 tool/scan_conditional_imports.py
python3 tool/scan_backend_boundary.py
python3 tool/scan_proxy_providers.py
/opt/flutter/bin/flutter build web --wasm --release
/opt/flutter/bin/flutter build linux --release
```

`flutter analyze` failing on an **info** lint has silently held the Pages deploy
twice for days. Run it *after* your last edit, not before.

There are three scans, not four. (An earlier plan named a `scan_raw_colors.py`
that has never existed.)

---

## Task 1 — Deploy `provider-proxy`. This is the one that unblocks the product.

**A paying member cannot generate an image.** The cause is settled, from reading
the *deployed* function source rather than the repository's:

- `provider-proxy` is **ACTIVE at version 1** — deployed once, ~2 August, never
  since.
- Its `openai.allow` is `['/v1/chat/completions', '/v1/responses']`. There is
  **no `/v1/images/generations`**. The repository has had it for weeks.
- It also predates the `_shift/routes` endpoint, so it cannot report its own
  version.

So the client is correct and the server is old. Nothing in the app can fix this.

**Two routes to deploy, in order of preference:**

1. **CI (durable).** `.github/workflows/backend.yml` has a `deploy-functions`
   job that exits 0 when its credentials are absent — they have never been set,
   so **it has never run once**. It needs, on the GitHub repo:
   - secret `SUPABASE_ACCESS_TOKEN`
   - variable `SUPABASE_PROJECT_REF` = `xmjaqizlrlsvjbwqmtdo`

   These are the owner's to add. The app now shows both as tappable rows with a
   copy button (Settings → Server settings). Once set, every push deploys.
   **This job has never executed, so expect first-contact failures** — watch the
   run and fix, don't declare it done on dispatch.

2. **Supabase MCP (immediate, if connected).** `python3 tool/bundle_function.py
   provider-proxy --deno` writes `build/functions/provider-proxy.deno.ts`, a
   single deployable file. Deploy that, plus `admin-membership`. The MCP
   disconnected three times in one session, so treat it as opportunistic.

**Verify by reading back what is running**, not what was sent: fetch the
deployed source and confirm it contains `/v1/images/generations` and the
`_shift/routes` branch. Then, on a phone: Settings → **Check** should say the
server forwards everything, and an image request should produce a picture.

**Do not touch `revenuecat-webhook`** — see Task 3.

---

## Task 2 — Settle whether `pause_turn` resume is worth building

`lib/providers/clients/anthropic_text.dart` handles Anthropic's `pause_turn`
stop reason by completing with what arrived and emitting a soft failure saying
the turn paused. **Resume is deliberately not implemented**: it needs the
assistant's raw content blocks carried through the event fold and re-posted as
`messages: [user, assistant(partial)]`, and there is no provider key in this
sandbox to confirm the resumed request is accepted.

This matters most on long web-search turns, which is exactly where it will be
hit. Either build it behind a bounded retry (2 resumes max) *and* say plainly
that it was never exercised against a real provider, or leave it and say why.
Do not ship an untested retry into the most expensive path in the app while
implying it was verified.

---

## Task 3 — Reconcile the payments story before building N8

**`revenuecat-webhook` is deployed and ACTIVE on the Supabase project, and does
not exist anywhere in this repository.** Two consequences:

1. A `supabase functions deploy` sweep from CI (Task 1) needs to know it is
   there, or it becomes an orphan nobody can find in source.
2. It implies a decision taken outside the repo — RevenueCat unifying StoreKit,
   Play Billing and Stripe into one entitlement — which is a **different shape**
   from the plan of record, which assumes three separate rails each writing the
   same `subscriptions` row. `supabase/functions/stripe-webhook/` exists and has
   never had keys.

Ask the owner which it is before writing payment code. Entitlement is currently
a manual admin grant; nothing can actually be bought on any platform.

---

## Standing rules — these are not negotiable

**Secrets never pass through a conversation.** `SUPABASE_ACCESS_TOKEN`,
`SUPABASE_DB_PASSWORD`, `SHIFT_KMS_KEY`, `ANDROID_KEYSTORE_BASE64` and its
password/alias, Stripe keys, and Apple/Google developer-portal credentials are
the owner's to handle. They travel from their clipboard to the encrypting
endpoint or to a settings form — never through a file you read, a commit, or a
chat message. **Anything pasted into a conversation is treated as compromised
and must be rotated.** `.gitignore` covers `.env*` with only `.env.example`
un-ignored; keep it that way.

**Do not open a pull request unless explicitly asked.**

**Break every new check on purpose before trusting it, and grep the break back
to confirm it applied.** This is not ceremony. In this codebase, checks have
repeatedly passed for the wrong reason:

- a scan compared the client to the repo's allowlist while the running server
  was five commits behind, and stayed green
- a card-position test ordered two widgets the test itself built, so deleting
  the card from the real screen left it passing
- a link check treated GitHub's `302` as success, and GitHub answers `302` for a
  missing asset too
- two break scripts silently matched nothing and came back green, which is
  indistinguishable from a test that cannot fail

**State the verification boundary in every report.** There is no provider key in
this sandbox, `*.supabase.co` and `*.github.io` are proxy-blocked, and there is
no macOS/Windows/iOS/Android runner. So: live provider behaviour is covered by
fake transports; the four non-Linux targets are verified as *built*, never as
*installed and run*; anything touching the deployed backend is only observable
from the owner's phone. Say this plainly rather than implying otherwise — every
field-reported defect in this project's history landed in exactly that gap.

---

## Architecture, in one screen

```
lib/
  core/        design tokens, platform shims, the self-updater
  data/        stores (KV-backed), artifacts, conversations, account
  turn/        planJobs(TurnRequest) -> JobGraph -> JobRunner + StepExecutor
  providers/   registry, capability selection, per-provider wire clients
  backend/     ShiftBackend seam — auth, entitlement, key vault, proxy
  features/    chat · code · visual · design · work · notes · settings · artifacts
supabase/      migrations (0001–0011) + edge functions
```

Conventions that will bite you if ignored:

- **Sealed types for exhaustiveness.** `TurnEvent`, `ChatItem`, `JobOutput`,
  `ProviderAccess`, `BackendProblem`. Adding a variant makes the analyzer name
  every switch that must learn about it — that is the point, don't add a
  default arm to silence it.
- **Conditional imports key on `dart.library.js_interop`, never
  `dart.library.html`** — the latter is false under dart2wasm and the wrong arm
  raises nothing at build time. Nine pairs; the scan checks them.
- **`lib/backend/` is a leaf.** Only `dart:async`, `dart:convert`,
  `package:http` and its own files. It may not import `features/ core/
  providers/ turn/ data/stores/`, and nothing outside it may name the vendor.
  `scan_backend_boundary.py` enforces both directions.
- **Pure decision / impure execution.** Anything that turns a status into a
  sentence, or a request into a plan, is a pure function with its own tests.
- **One widget per file, ~300 LOC ceiling**, and every interactive control
  clears `kMinTouchTarget` (44pt). That check has caught this app five times.
- **Comments explain *why*, and are expected to be corrected when reality
  disagrees.** A handler comment predicting the wrong HTTP status cost this
  project a week; when you find one, fix the comment, don't work around it.

The full history — every wave, every defect and every correction — is in
`/root/.claude/plans/i-need-to-build-greedy-micali.md`. It is long. Read the
sections you need rather than all of it.
