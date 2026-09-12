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
| HEAD | `f4ba833`, plus the Task 1 deploy below |
| Flutter | `/opt/flutter/bin/flutter` (3.44.9 — the SDK pin is `^3.12.0`, so 3.35 will not resolve) |
| Suite | 869 tests green |
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

## Task 1 — Deploy `provider-proxy`. ✅ Done — needs one confirmation on a phone.

**Deployed via the Supabase MCP on 14 August.** `provider-proxy` is now
**version 2** and `admin-membership` **version 2**, both from
`tool/bundle_function.py … --deno --lean`, both still `verify_jwt = true`.

Read back from the deployed source, not from what was sent:

- `openai.allow` now carries all five entries, **including
  `POST /v1/images/generations`** — the missing route that meant a paying member
  could not generate an image.
- The `_shift/routes` branch is present, so the server can report its own
  version from here on.
- `heygen` and `elevenlabs` exist upstream for the first time; `GET` is a
  permitted method, which is what makes the video-poll routes work.

**It also carried a second fix nobody had deployed.** `45ea926` ("One header,
blocked before it left the phone") fixed the preflight to reflect the browser's
own `Access-Control-Request-Headers`, and its own commit message records the
server half as *not* deployed. It was still not deployed. So every managed
Anthropic turn from a browser was being blocked at preflight — the CORS-shaped
failure this project has now misreported as a network one four times — and that
is fixed by the same version 2.

**The one thing that could not be checked from the sandbox.** `*.supabase.co` is
proxy-blocked here, so nothing was exercised end to end; `pg_net`/`http` are
available on the project but **not installed**, and installing an extension on
the production database to run a test is the owner's call, not a side effect of
a deploy. What *is* established: the deploy was accepted (so the bundle parses),
the version and `ezbr_sha256` both changed, and the read-back source contains
the routes above.

**Confirm on a phone, one check:** Settings → **Check** should report the server
forwards everything, and the version it reports should be

```
642ffea4
```

which is `routesVersion()` computed locally from `_shared/upstream.js`. A
different value means the deployed allowlist is not the repository's. (It was
`cc552813` until the multipart wave added `POST /v1/images/edits`; a copy of
this note quoting the old value is out of date, not a failed deploy.) Then send
an image request — that is the failure this task existed to clear.

**Still drifted: `provider-key`, at version 4 from 30 July.** It predates the
same CORS change. Left alone deliberately: it is the key vault, its existing
preflight list already covers the three headers the client sends it, and the
durable fix is the CI job below rather than another hand deploy.

**The durable fix is still not in place.** `.github/workflows/backend.yml` has a
`deploy-functions` job that exits 0 when its credentials are absent, so **it has
never run once**. It needs, on the GitHub repo:
- secret `SUPABASE_ACCESS_TOKEN`
- variable `SUPABASE_PROJECT_REF` = `xmjaqizlrlsvjbwqmtdo`

These are the owner's to add (Settings → Server settings has both as tappable
rows with a copy button). Until they are set, every deploy is a hand deploy, and
this drift comes back. **The job has never executed, so expect first-contact
failures** — watch the run and fix, don't declare it done on dispatch.

**Do not touch `revenuecat-webhook`** — it belongs to a different product
sharing this project. See Task 3.

**Multipart is now carried (14 Sep, version 3).** `provider-proxy` forwards a
`multipart/form-data` body with its boundary intact and its bytes unmangled, so
a photo can reach Sora as `input_reference`. Two independent bugs had to go:
`upstreamHeaders` overwrote the content type (destroying the boundary) and
`requestBody` read the body with `text()` (replacing every invalid UTF-8 byte
with U+FFFD). `POST /v1/images/edits` is allowed and priced as an image.

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

**Correction — this was wrong, and the mistake is worth keeping.** An earlier
version of this file read `revenuecat-webhook` as an unexplained SHIFT payments
decision, and told you to ask which billing shape SHIFT had settled on. It is
not SHIFT's at all.

**The Supabase project is shared with a second product.** Asking the live
database settles it: the 11th migration on the project is `songs_entitlements`
— *"Songs of the Church Plus"* — and its own comment says it is named `songs_*`
because *"this project already carries an unrelated public.subscriptions table
for another product"*. That migration is not in this repository, and neither is
the `revenuecat-webhook` function that writes to its table.

So: **leave both alone.** They are another app's, and the only thing SHIFT has
to do about them is not break them. Two consequences that do still stand:

1. A `supabase functions deploy` sweep from CI (Task 1) must not delete or
   overwrite `revenuecat-webhook`, which this repository has no source for.
2. Anything touching `public.subscriptions`, RLS, or grants is landing on a
   database another live product shares. Check `list_migrations` before
   assuming a migration ledger entry is SHIFT's.

**SHIFT's own payments are still unbuilt.** `supabase/functions/stripe-webhook/`
exists and has never had keys; entitlement is a manual admin grant; nothing can
be bought on any platform. Which rails SHIFT uses is still an open question for
N8 — it is just not answered by that webhook.

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
