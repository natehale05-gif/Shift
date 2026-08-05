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
 * @property {string[]} allow   `METHOD /path-prefix` entries a member may reach.
 * @property {(headers: Headers, key: string) => void} authorize
 *
 * The method is part of the entry rather than assumed, because video and
 * speech are asynchronous: submit with a POST, then poll a GET until the file
 * is ready. A proxy that only forwarded POSTs could start a video and never
 * collect it — which is how this table looked until video was added.
 *
 * It also keeps the allowlist honest in the other direction. `GET /v2/avatars`
 * is a list of what an account can use; `GET /v1/user/remaining_quota` is our
 * billing. Only one of those is a member's business, and writing the method
 * down makes the difference visible at the point you read the line.
 */

/** @type {Record<string, Upstream>} */
const UPSTREAMS = {
  anthropic: {
    host: 'https://api.anthropic.com',
    allow: ['POST /v1/messages'],
    authorize(headers, key) {
      headers.set('x-api-key', key);
      if (!headers.has('anthropic-version')) {
        headers.set('anthropic-version', '2023-06-01');
      }
    },
  },
  openai: {
    host: 'https://api.openai.com',
    // `/v1/images/generations` is here so a membership covers pictures, not
    // only words. It is priced separately — see `IMAGE_CALL_MICROS` — because
    // an image reports no tokens, and the flat unreported-call charge would
    // bill about a tenth of what one costs.
    allow: [
      'POST /v1/chat/completions',
      'POST /v1/responses',
      'POST /v1/images/generations',
      // Sora: submit, poll, then fetch the rendered file.
      'POST /v1/videos',
      'GET /v1/videos/',
    ],
    authorize: bearer,
  },
  gemini: {
    host: 'https://generativelanguage.googleapis.com',
    allow: ['POST /v1beta/models/'],
    authorize(headers, key) {
      // The header form, not `?key=`. A key in a query string is a key in
      // every access log and every error report between here and Google.
      headers.set('x-goog-api-key', key);
    },
  },
  groq: {
    host: 'https://api.groq.com/openai',
    allow: ['POST /v1/chat/completions'],
    authorize: bearer,
  },
  mistral: {
    host: 'https://api.mistral.ai',
    allow: ['POST /v1/chat/completions'],
    authorize: bearer,
  },
  openrouter: {
    host: 'https://openrouter.ai/api',
    allow: ['POST /v1/chat/completions'],
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
  heygen: {
    host: 'https://api.heygen.com',
    allow: [
      'POST /v2/video/generate',
      // The job is asynchronous: this is how a submitted video is collected.
      'GET /v1/video_status.get',
      // What this account can actually use. HeyGen retires stock avatars, and
      // a retired id is refused at submit, so asking is not optional.
      'GET /v2/avatars',
      'GET /v2/voices',
    ],
    authorize(headers, key) {
      headers.set('x-api-key', key);
    },
  },
  elevenlabs: {
    host: 'https://api.elevenlabs.io',
    allow: [
      'POST /v1/text-to-speech/',
      'POST /v1/music',
      'GET /v1/voices',
    ],
    authorize(headers, key) {
      // Their own header, not Bearer.
      headers.set('xi-api-key', key);
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
export function upstreamUrl(provider, path, search = '', method = 'POST') {
  const upstream = UPSTREAMS[provider];
  if (!upstream) return null;
  if (!path.startsWith('/') || path.includes('..') || path.includes('//')) {
    return null;
  }

  // The method is matched, not assumed. Video and speech submit with a POST
  // and collect with a GET, so both have to be allowed — and allowing GET
  // everywhere would open every provider's account endpoints, which are the
  // ones that describe *our* billing rather than a member's work.
  const wanted = method.toUpperCase();
  const permitted = upstream.allow.some((entry) => {
    const space = entry.indexOf(' ');
    return entry.slice(0, space) === wanted &&
        path.startsWith(entry.slice(space + 1));
  });
  if (!permitted) return null;

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

/**
 * Whether a path generates a picture rather than text.
 *
 * The distinction is a billing one, and it has to be made from the request
 * because the *reply* does not say: an image response carries no token counts,
 * so the meter sees nothing and the flat unreported-call charge applies —
 * about a tenth of what an image actually costs. A ceiling that under-counts
 * by 10x is not a ceiling.
 *
 * Gemini is the awkward case and is deliberately matched on the model rather
 * than the path: it generates images through the same `:generateContent` a
 * chat turn uses, and the only thing distinguishing them is which model was
 * asked.
 */
export function isImageCall(provider, path) {
  if (provider === 'openai') return path.startsWith('/v1/images/generations');
  if (provider === 'gemini') return path.includes('image');
  return false;
}

/**
 * What kind of work a call is, for pricing.
 *
 * Video and speech are asynchronous, so a single deliverable is one submit and
 * then a dozen polls. **Only the submit is charged.** Charging the polls would
 * make a two-minute render cost more in bookkeeping than in generation — at
 * the unreported-call rate, twenty-four polls is nearly fifty cents of pure
 * waiting — and the member did not ask for them; our own client did.
 *
 * That is safe rather than convenient: the GET entries in the allowlist are
 * status, listing and content. Nothing on that list generates anything, so
 * there is no way to turn a free call into work.
 *
 * @returns {'image' | 'video' | 'speech' | 'poll' | 'text'}
 */
export function callKind(provider, path, method = 'POST') {
  if (method.toUpperCase() === 'GET') return 'poll';
  if (isImageCall(provider, path)) return 'image';

  if (provider === 'heygen' && path.startsWith('/v2/video/generate')) {
    return 'video';
  }
  if (provider === 'openai' && path.startsWith('/v1/videos')) return 'video';
  if (provider === 'elevenlabs') return 'speech';

  return 'text';
}
