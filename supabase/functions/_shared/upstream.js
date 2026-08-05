// Where a proxied call is allowed to go, and how the key is attached.
//
// The client names a provider and a path. It does **not** name a host — that
// comes from this table and nowhere else. A proxy that forwarded to a
// client-supplied host would be an open relay holding SHIFT's provider keys,
// which is the worst possible thing to build here.
//
// The path is checked against a prefix allowlist for the same reason at one
// level down: `/v1/messages` is a chat call, `/v1/organizations/...` is account
// administration on our own provider account, and only the first is something
// a member is buying.

/**
 * @typedef {object} Upstream
 * @property {string} host      Fixed. Never client-supplied.
 * @property {string[]} allow   Path prefixes a member may reach.
 * @property {(headers: Headers, key: string) => void} authorize
 */

/** @type {Record<string, Upstream>} */
const UPSTREAMS = {
  anthropic: {
    host: 'https://api.anthropic.com',
    allow: ['/v1/messages'],
    authorize(headers, key) {
      headers.set('x-api-key', key);
      if (!headers.has('anthropic-version')) {
        headers.set('anthropic-version', '2023-06-01');
      }
    },
  },
  openai: {
    host: 'https://api.openai.com',
    allow: ['/v1/chat/completions', '/v1/responses'],
    authorize: bearer,
  },
  gemini: {
    host: 'https://generativelanguage.googleapis.com',
    allow: ['/v1beta/models/'],
    authorize(headers, key) {
      // The header form, not `?key=`. A key in a query string is a key in
      // every access log and every error report between here and Google.
      headers.set('x-goog-api-key', key);
    },
  },
  groq: {
    host: 'https://api.groq.com/openai',
    allow: ['/v1/chat/completions'],
    authorize: bearer,
  },
  mistral: {
    host: 'https://api.mistral.ai',
    allow: ['/v1/chat/completions'],
    authorize: bearer,
  },
  openrouter: {
    host: 'https://openrouter.ai/api',
    allow: ['/v1/chat/completions'],
    authorize(headers, key) {
      bearer(headers, key);
      // SHIFT identifying itself on SHIFT's own key — attached here rather
      // than by the member's device, which has no business knowing OpenRouter
      // asks for these. Sent from a browser they would also need CORS
      // permission the proxy has no reason to grant.
      headers.set('HTTP-Referer', 'https://shiftai.club');
      headers.set('X-Title', 'SHIFT AI');
    },
  },
};

function bearer(headers, key) {
  headers.set('Authorization', `Bearer ${key}`);
}

/** The providers a membership can spend through. */
export function proxyableProviders() {
  return Object.keys(UPSTREAMS);
}

export function upstreamFor(provider) {
  return UPSTREAMS[provider] ?? null;
}

/**
 * Splits `/functions/v1/provider-proxy/<provider>/<rest>` into its parts.
 *
 * Returns nulls rather than throwing, so the caller decides the status code —
 * and so a malformed path can never fall through to a request that is sent
 * anyway.
 */
export function parseProxyPath(pathname) {
  const marker = '/provider-proxy/';
  const at = pathname.indexOf(marker);
  if (at < 0) return { provider: null, path: null };

  const rest = pathname.slice(at + marker.length);
  const slash = rest.indexOf('/');
  if (slash <= 0) return { provider: null, path: null };

  return {
    provider: rest.slice(0, slash).toLowerCase(),
    path: rest.slice(slash),
  };
}

/**
 * The URL to call upstream, or null when the path is not one this proxy will
 * forward.
 *
 * Rejects `..` outright rather than trying to normalise it. Normalising is the
 * kind of thing that looks right and has a bypass; refusing is the kind that
 * does not.
 */
export function upstreamUrl(provider, path, search = '') {
  const upstream = UPSTREAMS[provider];
  if (!upstream) return null;
  if (!path.startsWith('/') || path.includes('..') || path.includes('//')) {
    return null;
  }
  if (!upstream.allow.some((prefix) => path.startsWith(prefix))) return null;

  // A `key` parameter in the query would be a caller trying to substitute its
  // own credential, or to smuggle one into our logs. Neither is wanted.
  const params = new URLSearchParams(search.startsWith('?') ? search.slice(1) : search);
  params.delete('key');
  params.delete('api_key');
  const query = params.toString();

  return `${upstream.host}${path}${query ? `?${query}` : ''}`;
}

/**
 * The headers to send upstream: the caller's, minus everything that belongs to
 * *our* edge (its auth, its host) or that would let the caller choose its own
 * credential, plus the provider's.
 */
export function upstreamHeaders(provider, incoming, key) {
  const headers = new Headers();
  for (const [name, value] of incoming) {
    if (STRIPPED.has(name.toLowerCase())) continue;
    headers.set(name, value);
  }
  headers.set('Content-Type', 'application/json');
  UPSTREAMS[provider].authorize(headers, key);
  return headers;
}

/**
 * Headers that must not be forwarded.
 *
 * `authorization` and `apikey` are the member's session, not a provider
 * credential — forwarding them would hand a third party a token that can read
 * this account. `x-api-key` and `x-goog-api-key` are dropped so a caller cannot
 * pre-set the credential and have it survive; `authorize()` sets them after.
 */
const STRIPPED = new Set([
  'authorization',
  'apikey',
  'x-api-key',
  'x-goog-api-key',
  'host',
  'content-length',
  'connection',
  'cookie',
  'origin',
  'referer',
]);
