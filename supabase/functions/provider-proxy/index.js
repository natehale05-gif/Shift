// Spend SHIFT's provider keys on behalf of a paying member.
//
// This is the endpoint that makes a membership worth anything: the member's
// device never holds a provider key, never sees one, and cannot obtain one.
// It sends the same request body it would have sent directly, to us instead,
// with its own session token — and we attach the credential, forward, stream
// the answer straight back, and write down what it cost.
//
// Four things have to be true at once, and each is a way to lose money or
// leak a key if it is wrong:
//
//   1. The caller is signed in.                  (the gateway, plus `subjectOf`)
//   2. The caller is entitled and under budget.  (`shift.within_ceiling`)
//   3. The destination is one we chose.          (`_shared/upstream.js`)
//   4. The call is metered, even when the        (`_shared/usage_meter.js`
//      provider reports nothing.                  plus UNREPORTED_CALL_MICROS)
//
// The response is streamed, not buffered. A chat reply takes tens of seconds
// and arrives a token at a time; holding it to count tokens first would turn a
// live conversation into a long wait and a wall of text.

import { masterKeyBytes, open, hexToBytes } from '../_shared/crypto.js';
import {
  corsHeaders,
  problem,
  requireEnv,
  serviceRequest,
  withAdapter,
} from '../_shared/handler.js';
import {
  costMicros,
  fixedPriceFor,
  UNREPORTED_CALL_MICROS,
} from '../_shared/pricing.js';
import {
  callKind,
  parseProxyPath,
  upstreamFor,
  upstreamHeaders,
  upstreamUrl,
} from '../_shared/upstream.js';
import { meteredBody, UsageMeter } from '../_shared/usage_meter.js';

export const handle = withAdapter(async (req, ctx) => {
  // GET as well as POST, because video and speech are asynchronous: the work
  // is submitted with a POST and collected with a GET. A proxy that forwarded
  // only POSTs could start a video and never fetch it — which is exactly what
  // it did until video was added.
  //
  // Which GETs are reachable is the allowlist's business, not this line's:
  // every entry carries its method, so `GET /v2/avatars` is permitted and
  // `GET` to an account endpoint is not.
  if (req.method !== 'POST' && req.method !== 'GET') {
    return problem(405, 'Use POST or GET.');
  }

  const url = new URL(req.url);
  const { provider, path } = parseProxyPath(url.pathname);
  if (!provider || !upstreamFor(provider)) {
    return problem(404, 'Unknown provider.');
  }

  const target = upstreamUrl(provider, path, url.search, req.method);
  if (!target) {
    // Deliberately vague. Naming which prefixes are allowed tells someone
    // probing this endpoint exactly what to try next.
    return problem(403, 'That endpoint is not available through SHIFT.');
  }

  // Three answers, not two. "The plan says no" and "the check could not run"
  // are both reasons to refuse, and collapsing them is how a 402 came to
  // announce that a member's plan did not cover them while their plan covered
  // them perfectly — the check was 404ing and failing closed, correctly and
  // silently. Refusing either way is right; saying the same sentence is not.
  const entitled = await withinCeiling(ctx);
  if (entitled === 'unknown') {
    return problem(503, 'Could not check your plan right now.');
  }
  if (!entitled) {
    return problem(
      402,
      'Your plan does not cover this right now — either it is inactive or ' +
        'you have used everything it includes this month. Your own API key ' +
        'still works in Settings.',
    );
  }

  // Checked before the vault is touched, and reported rather than swallowed.
  //
  // Without this, a missing `SHIFT_KMS_KEY` throws inside `masterKeyBytes`,
  // the adapter turns it into a bare 500, and the Setup card reads that as
  // "the provider is having trouble right now" — pointing at Anthropic for a
  // variable on our own server. Naming the variable is not echoing a secret:
  // the no-echo rule in `handler.js` is about values, and this is a pre-check
  // rather than a caught exception being quoted back.
  //
  // 503 rather than a status of its own, because it means what 503 already
  // means here — the server is running but not finished being set up — and the
  // person who fixes it is the same person.
  const missing = requiredEnv.filter((name) => !ctx.env[name]);
  if (missing.length > 0) {
    return problem(503, `The server is missing ${missing.join(', ')}.`);
  }

  const secret = await platformKey(ctx, provider);
  if (!secret) {
    return problem(
      503,
      `${provider} is not one of the providers SHIFT currently covers.`,
    );
  }

  // A GET has no body, and sending one is how a well-behaved server starts
  // answering 400 to a request that was otherwise correct.
  const body = req.method === 'POST' ? await requestBody(req, provider) : null;
  const headers = upstreamHeaders(provider, req.headers, secret);
  if (body !== null) betaHeadersFor(provider, body, headers);

  const upstream = await ctx.fetch(target, {
    method: req.method,
    headers,
    ...(body === null ? {} : { body }),
  });

  const meter = new UsageMeter();
  const kind = callKind(provider, path, req.method);
  const streamed = meteredBody(upstream.body, meter, (finished) => {
    // Floating on purpose: the member's reply must not wait on our
    // bookkeeping. A failure here is logged and swallowed for the same reason
    // — a metering error is not a reason to break a conversation.
    record(ctx, provider, finished, kind).catch((error) => {
      console.error('usage not recorded', error);
    });
  });

  return new Response(streamed, {
    status: upstream.status,
    headers: responseHeaders(upstream.headers),
  });
});

export default { fetch: (req) => handle(req, { env: readEnv() }) };

function readEnv() {
  // eslint-disable-next-line no-undef
  if (typeof Deno !== 'undefined') return Deno.env.toObject();
  return globalThis.process?.env ?? {};
}

/**
 * Whether this account may spend a managed call right now.
 *
 * Asked of the database rather than worked out here: `shift.within_ceiling` is
 * the same function the schema's own tests assert, so there is one definition
 * of "entitled" and not a second one that can drift from it. `0011` is what
 * makes it reachable — the definition lives in `shift`, and PostgREST only
 * serves `public`.
 *
 * Returns `true`, `false`, or `'unknown'`. A failure still refuses — an
 * entitlement check that fails open is not a check — but the caller reports it
 * as our problem rather than as the member's plan, because for four weeks it
 * was ours and the message said theirs.
 *
 * @returns {Promise<boolean | 'unknown'>}
 */
async function withinCeiling(ctx) {
  try {
    const response = await serviceRequest(ctx, '/rpc/within_ceiling', {
      method: 'POST',
      body: JSON.stringify({ account: ctx.userId }),
    });
    return (await response.json()) === true;
  } catch (error) {
    console.error('ceiling check failed', error);
    return 'unknown';
  }
}

/** Decrypts SHIFT's key for [provider], or null when there is not one. */
async function platformKey(ctx, provider) {
  const response = await serviceRequest(
    ctx,
    `/platform_keys?provider=eq.${encodeURIComponent(provider)}` +
      '&enabled=is.true&select=ciphertext',
  );
  const rows = await response.json();
  const ciphertext = Array.isArray(rows) ? rows[0]?.ciphertext : null;
  if (typeof ciphertext !== 'string' || ciphertext.length === 0) return null;

  // PostgREST renders `bytea` as a hex string with a leading `\x`.
  const hex = ciphertext.startsWith('\\x') ? ciphertext.slice(2) : ciphertext;
  return open(hexToBytes(hex), masterKeyBytes(ctx.env));
}

/**
 * The body to forward.
 *
 * Passed through untouched except for one thing: OpenAI-compatible providers
 * only report usage on a streamed call if asked to, and a member's client has
 * no reason to ask. Without this the meter would read zero for every OpenAI,
 * Groq, Mistral and OpenRouter call, and the fallback charge would apply to
 * all of them — accurate metering is better than a flat guess.
 */
async function requestBody(req, provider) {
  const raw = await req.text();
  if (!OPENAI_SHAPED.has(provider)) return raw;

  try {
    const parsed = JSON.parse(raw);
    if (parsed?.stream === true) {
      parsed.stream_options = { ...(parsed.stream_options ?? {}), include_usage: true };
      return JSON.stringify(parsed);
    }
  } catch {
    // Not JSON we understand. Forward it as it came and let the provider be
    // the one to complain — it knows its own API better than we do.
  }
  return raw;
}

const OPENAI_SHAPED = new Set(['openai', 'groq', 'mistral', 'openrouter']);

/**
 * Opt-in headers a provider requires for a feature the *body* asks for.
 *
 * Anthropic's code execution needs `anthropic-beta`, and a member's device
 * cannot send it: every header beyond the CORS-simple set makes the browser
 * preflight, and that is how `anthropic-version` came to block every managed
 * turn. So the capability moves to the side holding the key — the request the
 * proxy is already forwarding says what it wants, and the proxy asks for it.
 *
 * Read from the body rather than trusted from a header for the same reason:
 * the body is the thing the provider will act on.
 */
function betaHeadersFor(provider, body, headers) {
  if (provider !== 'anthropic' || typeof body !== 'string') return;

  let parsed;
  try {
    parsed = JSON.parse(body);
  } catch {
    return; // Not ours to interpret. Forward it as it came.
  }

  const tools = Array.isArray(parsed?.tools) ? parsed.tools : [];
  const wantsCodeExecution = tools.some(
    (tool) => typeof tool?.type === 'string' && tool.type.startsWith('code_execution'),
  );
  if (wantsCodeExecution && !headers.has('anthropic-beta')) {
    headers.set('anthropic-beta', CODE_EXECUTION_BETA);
  }
}

/**
 * Must equal `AnthropicTools.codeExecutionBeta` on the client.
 *
 * A second copy of a constant, checked rather than remembered:
 * `tool/scan_proxy_providers.py` fails the build if the two drift. Wrong here,
 * the provider rejects a tool the client believes it enabled — which reads as
 * the model refusing to run code, not as a mismatched string.
 */
const CODE_EXECUTION_BETA = 'code-execution-2025-08-25';

/**
 * Writes the usage row.
 *
 * A call that reported nothing is still charged [UNREPORTED_CALL_MICROS].
 * Zero would make "return a shape the meter does not understand" into a way to
 * spend SHIFT's keys for free.
 */
async function record(ctx, provider, meter, kind = 'text') {
  // Pictures, video and speech are priced per call, because their replies
  // carry no token counts for the meter to read. Left to the unreported-call
  // charge, an image bills about a tenth of what one costs and a video a
  // fortieth — and a ceiling that under-counts by that much does not bound
  // anything.
  //
  // The fixed price is checked *before* `sawUsage`, deliberately. Gemini
  // generates pictures through the same endpoint as a chat turn and does
  // report tokens for them, which would otherwise price a picture as a short
  // conversation. And a poll priced at zero must stay zero even though the
  // status body it returns is perfectly parseable.
  const fixed = fixedPriceFor(kind);
  const cost = fixed !== null
    ? fixed
    : meter.sawUsage
        ? costMicros({
            model: meter.model,
            inputTokens: meter.inputTokens,
            outputTokens: meter.outputTokens,
          })
        : UNREPORTED_CALL_MICROS;

  await serviceRequest(ctx, '/usage_events', {
    method: 'POST',
    headers: { Prefer: 'return=minimal' },
    body: JSON.stringify({
      owner_id: ctx.userId,
      provider,
      model: meter.model,
      key_owner: 'managed',
      input_tokens: meter.inputTokens,
      output_tokens: meter.outputTokens,
      cost_micros: cost,
    }),
  });
}

/**
 * The headers to send back.
 *
 * An allowlist rather than a pass-through: upstream sets `set-cookie`,
 * rate-limit counters for *our* account, and organisation ids, none of which
 * are a member's business and some of which describe SHIFT's own usage across
 * every member.
 */
function responseHeaders(from) {
  const headers = new Headers(corsHeaders());
  for (const name of ['content-type', 'cache-control']) {
    const value = from.get(name);
    if (value) headers.set(name, value);
  }
  return headers;
}

/**
 * Everything this function cannot work without. Read by the handler above so a
 * missing one is a sentence rather than a 500, and exported so a test can
 * assert against the list rather than restate it.
 */
export const requiredEnv = ['SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY', 'SHIFT_KMS_KEY'];
export { requireEnv };
