// The thin adapter every function sits behind.
//
// Handlers below are plain `(Request, context) => Response`. Nothing in them
// imports a Supabase library, so the bodies port to Node, Bun or Workers by
// swapping this file — which is the same trick `lib/backend/` plays on the
// client, for the same reason.
//
// It is also what makes them testable without a running platform: a test calls
// `handle(new Request(...), {env, fetch})` and asserts the Response.

/**
 * Wraps a handler with the things every endpoint needs: CORS, JSON errors, and
 * one place where an unexpected throw becomes a 500 instead of a stack trace in
 * the response body.
 *
 * @param {(req: Request, ctx: {env: Record<string,string|undefined>, fetch: typeof globalThis.fetch, userId: string|null}) => Promise<Response>} handler
 * @param {{requireAuth?: boolean}} [options]
 */
export function withAdapter(handler, options = {}) {
  const requireAuth = options.requireAuth !== false;

  return async function handle(req, ctx = {}) {
    const env = ctx.env ?? {};
    const doFetch = ctx.fetch ?? globalThis.fetch;

    if (req.method === 'OPTIONS') {
      return new Response(null, {
        status: 204,
        headers: corsHeaders(req.headers.get('Access-Control-Request-Headers')),
      });
    }

    let userId = null;
    if (requireAuth) {
      userId = subjectOf(req.headers.get('Authorization'));
      if (!userId) {
        return problem(401, 'Sign in to do that.');
      }
    }

    try {
      return await handler(req, { env, fetch: doFetch, userId });
    } catch (error) {
      // Never echo the error to the caller. These handlers hold decryption
      // keys and provider secrets, and an exception message is exactly the
      // kind of thing that quotes one back.
      console.error('handler failed', error);
      return problem(500, 'Something went wrong.');
    }
  };
}

/**
 * The `sub` claim, read without verifying the signature.
 *
 * **This is not authentication.** The gateway in front of these functions
 * verifies the JWT, and every database write below goes through PostgREST with
 * the caller's own token so row security applies regardless. Reading the claim
 * here is only so a handler can name the account without a round trip — if this
 * were the only check, a forged token would walk straight in.
 *
 * @param {string | null} authorization
 * @returns {string | null}
 */
export function subjectOf(authorization) {
  if (!authorization?.startsWith('Bearer ')) return null;
  const parts = authorization.slice(7).split('.');
  if (parts.length !== 3) return null;
  try {
    const payload = JSON.parse(
      new TextDecoder().decode(base64UrlToBytes(parts[1])),
    );
    const sub = payload?.sub;
    return typeof sub === 'string' && sub.length > 0 ? sub : null;
  } catch {
    return null;
  }
}

/** A JSON error the client's `BackendProblem` mapping already understands. */
export function problem(status, message) {
  return json({ message }, status);
}

export function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', ...corsHeaders() },
  });
}

/**
 * CORS, with the preflight's own header list echoed back.
 *
 * **Why reflected rather than listed.** `provider-proxy` is a transparent
 * passthrough, so the browser sends whatever the provider's API asks for —
 * Anthropic needs `anthropic-version` on every call, and each provider has its
 * own. A fixed list was the bug: it named `authorization, apikey,
 * content-type`, which is exactly what the Setup card's test call sends, so the
 * test passed while every real turn failed its preflight. The browser then
 * reports a blocked preflight as no answer at all, so the app said "could not
 * reach the provider" — the third time in this project that a CORS-shaped
 * failure has been reported as a network one.
 *
 * A fixed list would also have to grow every time a provider adds a header,
 * which is a maintenance edge nobody would notice until a turn broke.
 *
 * **This is not an authorization decision.** `Access-Control-Allow-Headers`
 * answers "may the browser send these", not "may the caller do this" — the
 * gateway's JWT check and the entitlement check answer that, and they run
 * either way. With `Allow-Origin: *` browsers refuse to send cookies at all,
 * so there is no ambient credential for a reflected header to unlock.
 *
 * @param {string | null} [requested] the preflight's Access-Control-Request-Headers
 */
export function corsHeaders(requested) {
  return {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers':
      requested && requested.trim().length > 0
        ? requested
        : 'authorization, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, GET, DELETE, OPTIONS',
    // Without this the browser preflights every single turn, which is a round
    // trip before a word of the reply can start streaming.
    'Access-Control-Max-Age': '86400',
  };
}

/**
 * A PostgREST call as the service role.
 *
 * Confined to this file on purpose: the service role bypasses row security, so
 * every use of it is a place where a mistake reads somebody else's data. Keeping
 * it in one function means there is one place to audit rather than one per
 * handler.
 */
export async function serviceRequest(ctx, path, init = {}) {
  const url = requireEnv(ctx.env, 'SUPABASE_URL');
  const key = requireEnv(ctx.env, 'SUPABASE_SERVICE_ROLE_KEY');
  const response = await ctx.fetch(`${url}/rest/v1${path}`, {
    ...init,
    headers: {
      apikey: key,
      Authorization: `Bearer ${key}`,
      'Content-Type': 'application/json',
      ...(init.headers ?? {}),
    },
  });
  if (!response.ok) {
    throw new Error(`PostgREST ${response.status}: ${await response.text()}`);
  }
  return response;
}

export function requireEnv(env, name) {
  const value = env[name];
  if (!value) throw new Error(`${name} is not set.`);
  return value;
}

function base64UrlToBytes(value) {
  const padded = value.replace(/-/g, '+').replace(/_/g, '/');
  const binary = atob(padded.padEnd(Math.ceil(padded.length / 4) * 4, '='));
  const out = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) out[i] = binary.charCodeAt(i);
  return out;
}
