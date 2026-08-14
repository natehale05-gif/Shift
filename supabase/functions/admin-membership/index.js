// Grant or adjust an account's membership.
//
// Until Stripe exists nothing can make an account paid, which meant the only
// way to try the proxy was a hand-written `insert into subscriptions` in a SQL
// editor — on a phone. This is that statement, as a button.
//
// **It does not loosen what `0004` established.** A client still holds no
// write grant on `subscriptions`, and `rls_test.sql` still asserts that a
// member cannot grant themselves a membership. What this adds is an *admin*
// endpoint, the same shape as the platform scope of `provider-key`: the check
// is `profiles.is_admin`, read here with the service role, against a column no
// client can write. A non-admin gets the same bare 403 and learns nothing.
//
// Comping an account is also a thing a real product needs — a founding member,
// a refund, a support case — so this outlives the gap it was built for.

import {
  problem,
  json,
  serviceRequest,
  withAdapter,
} from '../_shared/handler.js';

/** Statuses this endpoint may set. `past_due` belongs to Stripe alone. */
const SETTABLE = new Set(['none', 'trialing', 'active', 'canceled']);

/**
 * The most an admin may hand out in one call, in millionths of a dollar.
 *
 * $500. Not because an admin cannot be trusted, but because this is a number
 * typed into a phone: a mistyped ceiling is a real way to lose money, and no
 * legitimate comp needs more than this. Raising it is a deploy, which is the
 * right amount of friction for a decision that size.
 */
const MAX_CEILING_MICROS = 500_000_000;

export const handle = withAdapter(async (req, ctx) => {
  if (req.method !== 'POST') return problem(405, 'Use POST.');

  if (!(await isAdmin(ctx))) {
    // Bare, like `provider-key`'s. Saying "you are not an admin" to someone
    // who found this confirms the endpoint is worth attacking.
    return problem(403, 'Not allowed.');
  }

  let body;
  try {
    body = await req.json();
  } catch {
    return problem(400, 'Expected a JSON body.');
  }

  const status = String(body?.status ?? 'active');
  if (!SETTABLE.has(status)) {
    return problem(400, `Cannot set status "${status}".`);
  }

  const ceiling = Math.trunc(Number(body?.ceilingMicros ?? 0));
  if (!Number.isFinite(ceiling) || ceiling < 0) {
    return problem(400, 'The ceiling must be a positive number.');
  }
  if (ceiling > MAX_CEILING_MICROS) {
    return problem(
      400,
      `That ceiling is above the ${MAX_CEILING_MICROS / 1_000_000} dollar ` +
        'limit for a granted membership.',
    );
  }

  // Who it is for. Defaults to the caller, because granting yourself the first
  // membership is the case that exists today; an email covers the rest.
  const email = String(body?.email ?? '').trim().toLowerCase();
  const ownerId = email.length > 0 ? await idForEmail(ctx, email) : ctx.userId;
  if (!ownerId) {
    // Safe to say plainly: an admin is asking about an account they named.
    return problem(404, `No account with the address ${email}.`);
  }

  await serviceRequest(ctx, '/subscriptions?on_conflict=owner_id', {
    method: 'POST',
    headers: { Prefer: 'resolution=merge-duplicates,return=minimal' },
    body: JSON.stringify({
      owner_id: ownerId,
      status,
      plan: String(body?.plan ?? 'granted'),
      spend_ceiling_micros: ceiling,
      updated_at: new Date().toISOString(),
    }),
  });

  return json({ owner_id: ownerId, status, ceiling_micros: ceiling });
});

export default { fetch: (req) => handle(req, { env: readEnv() }) };

function readEnv() {
  // eslint-disable-next-line no-undef
  if (typeof Deno !== 'undefined') return Deno.env.toObject();
  return globalThis.process?.env ?? {};
}

/** Same check, same reasoning, as `provider-key`'s platform scope. */
async function isAdmin(ctx) {
  const response = await serviceRequest(
    ctx,
    `/profiles?id=eq.${encodeURIComponent(ctx.userId)}&select=is_admin`,
  );
  const rows = await response.json();
  return Array.isArray(rows) && rows[0]?.is_admin === true;
}

/** The account id behind an address, or null when there is not one. */
async function idForEmail(ctx, email) {
  const response = await serviceRequest(
    ctx,
    `/profiles?email=eq.${encodeURIComponent(email)}&select=id`,
  );
  const rows = await response.json();
  return Array.isArray(rows) && rows[0]?.id ? rows[0].id : null;
}
