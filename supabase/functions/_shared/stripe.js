// Stripe webhook signature verification, and the mapping from a Stripe
// subscription to the row we store.
//
// WebCrypto only, like everything else here, so it runs on Deno, Node, Bun and
// Workers unchanged — and so it can be tested without Stripe.
//
// This is the security-critical file in the billing path. A webhook endpoint
// that does not verify signatures is a public endpoint that anyone can POST
// "this account is now a paying member" to.

/**
 * Verifies a `Stripe-Signature` header against the raw body.
 *
 * Returns the parsed event, or throws. Never returns a partly-trusted result:
 * a caller that has to remember to check a boolean will eventually forget.
 *
 * @param {string} payload raw request body, byte for byte as received
 * @param {string | null} header the `Stripe-Signature` value
 * @param {string} secret the endpoint's signing secret
 * @param {number} [toleranceSeconds] how old a signature may be
 * @param {number} [nowSeconds] injectable clock, for tests
 */
export async function verifyStripeSignature(
  payload,
  header,
  secret,
  toleranceSeconds = 300,
  nowSeconds = Math.floor(Date.now() / 1000),
) {
  if (!header) throw new Error('Missing signature.');
  if (!secret) throw new Error('Webhook secret is not set.');

  const parts = Object.fromEntries(
    header
      .split(',')
      .map((piece) => piece.split('='))
      .filter((pair) => pair.length === 2)
      .map(([k, v]) => [k.trim(), v.trim()]),
  );

  const timestamp = Number(parts.t);
  if (!Number.isFinite(timestamp)) throw new Error('Malformed signature.');

  // Without this a signature captured once can be replayed forever — the
  // signature stays valid, because the payload never changes.
  if (Math.abs(nowSeconds - timestamp) > toleranceSeconds) {
    throw new Error('Signature is outside the tolerance window.');
  }

  const expected = await hmacHex(secret, `${timestamp}.${payload}`);
  // Stripe may send several v1 signatures during a secret rotation; any one
  // matching is a valid request.
  const offered = header
    .split(',')
    .map((piece) => piece.split('='))
    .filter(([k]) => k.trim() === 'v1')
    .map(([, v]) => v.trim());

  if (!offered.some((candidate) => timingSafeEqual(candidate, expected))) {
    throw new Error('Signature does not match.');
  }

  return JSON.parse(payload);
}

async function hmacHex(secret, message) {
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const signature = new Uint8Array(
    await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(message)),
  );
  let hex = '';
  for (const byte of signature) hex += byte.toString(16).padStart(2, '0');
  return hex;
}

/**
 * Compares without returning early on the first difference.
 *
 * `a === b` on a secret leaks how much of a guess was right through how long
 * the comparison took. The leak is small over a network and free to avoid.
 */
export function timingSafeEqual(a, b) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

/** Stripe's subscription statuses, narrowed to the ones the schema allows. */
export function statusFor(stripeStatus) {
  switch (stripeStatus) {
    case 'trialing':
      return 'trialing';
    case 'active':
      return 'active';
    case 'past_due':
    case 'unpaid':
      return 'past_due';
    case 'canceled':
    case 'incomplete_expired':
      return 'canceled';
    default:
      // `incomplete` and anything Stripe adds later: not paying yet, and the
      // safe reading of "we do not recognise this" is "not entitled".
      return 'none';
  }
}

/**
 * The spend ceiling a plan carries, in millionths of a dollar.
 *
 * Kept beside the status mapping because the two always change together: a new
 * plan with no ceiling would be an unbounded bill, and defaulting an unknown
 * plan to zero is what makes forgetting to add one fail closed.
 */
export function ceilingFor(plan) {
  switch (plan) {
    case 'starter':
      return 5_000_000; // $5
    case 'pro':
      return 25_000_000; // $25
    case 'studio':
      return 100_000_000; // $100
    default:
      return 0;
  }
}
