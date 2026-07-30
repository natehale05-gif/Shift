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
      return new Response(null, { status: 204, headers: corsHeaders() });
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

export function corsHeaders() {
  return {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, GET, DELETE, OPTIONS',
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
