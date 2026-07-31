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
import { costMicros, UNREPORTED_CALL_MICROS } from '../_shared/pricing.js';
import {
  parseProxyPath,
  upstreamFor,
  upstreamHeaders,
  upstreamUrl,
} from '../_shared/upstream.js';
import { meteredBody, UsageMeter } from '../_shared/usage_meter.js';

export const handle = withAdapter(async (req, ctx) => {
  if (req.method !== 'POST') return problem(405, 'Use POST.');

  const url = new URL(req.url);
  const { provider, path } = parseProxyPath(url.pathname);
  if (!provider || !upstreamFor(provider)) {
    return problem(404, 'Unknown provider.');
  }

  const target = upstreamUrl(provider, path, url.search);
  if (!target) {
    // Deliberately vague. Naming which prefixes are allowed tells someone
    // probing this endpoint exactly what to try next.
    return problem(403, 'That endpoint is not available through SHIFT.');
  }

  if (!(await withinCeiling(ctx))) {
    return problem(
      402,
      'Your plan does not cover this right now — either it is inactive or ' +
        'you have used everything it includes this month. Your own API key ' +
        'still works in Settings.',
    );
  }

  const secret = await platformKey(ctx, provider);
  if (!secret) {
    return problem(
      503,
      `${provider} is not one of the providers SHIFT currently covers.`,
    );
  }

  const body = await requestBody(req, provider);
  const upstream = await ctx.fetch(target, {
    method: 'POST',
    headers: upstreamHeaders(provider, req.headers, secret),
    body,
  });

  const meter = new UsageMeter();
  const streamed = meteredBody(upstream.body, meter, (finished) => {
    // Floating on purpose: the member's reply must not wait on our
    // bookkeeping. A failure here is logged and swallowed for the same reason
    // — a metering error is not a reason to break a conversation.
    record(ctx, provider, finished).catch((error) => {
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
 * Asked of the database rather than worked out here: `shift.within_ceiling`
 * is the same function the schema's own tests assert, so there is one
 * definition of "entitled" and not a second one that can drift from it.
 *
 * Any failure answers no. An entitlement check that fails open is not a check.
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
    return false;
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
 * Writes the usage row.
 *
 * A call that reported nothing is still charged [UNREPORTED_CALL_MICROS].
 * Zero would make "return a shape the meter does not understand" into a way to
 * spend SHIFT's keys for free.
 */
async function record(ctx, provider, meter) {
  const cost = meter.sawUsage
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

// Only referenced so a bundler cannot decide it is unused; the env var is what
// makes the whole thing work and its absence should fail loudly at boot.
export const requiredEnv = ['SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY', 'SHIFT_KMS_KEY'];
export { requireEnv };
