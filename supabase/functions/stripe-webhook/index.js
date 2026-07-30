// Stripe tells us what somebody is entitled to. Nothing else may.
//
// `subscriptions` is read-only to `authenticated` in the schema, so a client
// cannot grant itself a membership. This endpoint is the other half of that:
// it is the only writer, and it only writes what a *verified* Stripe event
// says.
//
// Unauthenticated by design — Stripe has no JWT. The signature is the
// authentication, which is why the verification is the first thing that
// happens and why a failure here returns 400 without touching the database.

import { json, problem, serviceRequest, withAdapter } from '../_shared/handler.js';
import {
  ceilingFor,
  statusFor,
  verifyStripeSignature,
} from '../_shared/stripe.js';

export const handle = withAdapter(
  async (req, ctx) => {
    if (req.method !== 'POST') return problem(405, 'Use POST.');

    const payload = await req.text();

    let event;
    try {
      event = await verifyStripeSignature(
        payload,
        req.headers.get('Stripe-Signature'),
        ctx.env.SHIFT_STRIPE_WEBHOOK_SECRET,
      );
    } catch (error) {
      // 400, not 500: a bad signature is a rejected request, and Stripe retries
      // 5xx. Retrying a forgery forever would be the wrong thing to ask for.
      console.error('rejected webhook', error.message);
      return problem(400, 'Signature verification failed.');
    }

    const handled = new Set([
      'customer.subscription.created',
      'customer.subscription.updated',
      'customer.subscription.deleted',
      'checkout.session.completed',
    ]);

    // Acknowledged, not acted on. Stripe retries anything that is not 2xx, so
    // returning an error for an event we simply do not care about would build a
    // permanent queue of failures.
    if (!handled.has(event?.type)) return json({ ignored: event?.type ?? null });

    const object = event.data?.object ?? {};

    if (event.type === 'checkout.session.completed') {
      // The session carries the account id we put in `client_reference_id` when
      // we created it — this is the only point where a Stripe customer is tied
      // to a SHIFT account, so it has to be the value we sent, never one the
      // payload invents.
      const ownerId = object.client_reference_id;
      if (!ownerId) return json({ ignored: 'no client_reference_id' });

      await upsert(ctx, {
        owner_id: ownerId,
        stripe_customer_id: object.customer ?? null,
        stripe_subscription_id: object.subscription ?? null,
        status: 'active',
        plan: object.metadata?.plan ?? null,
        spend_ceiling_micros: ceilingFor(object.metadata?.plan),
        updated_at: new Date().toISOString(),
      });
      return json({ ok: true });
    }

    // Subscription events identify the account by customer, because by now the
    // link already exists.
    const customer = object.customer;
    if (!customer) return json({ ignored: 'no customer' });

    const plan = object.metadata?.plan ?? object.items?.data?.[0]?.price?.nickname ?? null;
    const status =
      event.type === 'customer.subscription.deleted'
        ? 'canceled'
        : statusFor(object.status);

    const response = await serviceRequest(
      ctx,
      `/subscriptions?stripe_customer_id=eq.${encodeURIComponent(customer)}`,
      {
        method: 'PATCH',
        headers: { Prefer: 'return=representation' },
        body: JSON.stringify({
          status,
          plan,
          // A cancelled subscription keeps its row but loses its ceiling, so a
          // stale `active` read anywhere still cannot spend.
          spend_ceiling_micros: status === 'canceled' ? 0 : ceilingFor(plan),
          stripe_subscription_id: object.id ?? null,
          current_period_end: object.current_period_end
            ? new Date(object.current_period_end * 1000).toISOString()
            : null,
          updated_at: new Date().toISOString(),
        }),
      },
    );

    const rows = await response.json();
    if (!Array.isArray(rows) || rows.length === 0) {
      // A customer we have never seen. Acknowledged so Stripe stops retrying,
      // and logged, because it means a checkout completed without its session
      // event arriving — worth knowing about.
      console.error('subscription event for unknown customer', customer);
      return json({ ignored: 'unknown customer' });
    }

    return json({ ok: true });
  },
  { requireAuth: false },
);

async function upsert(ctx, row) {
  await serviceRequest(ctx, '/subscriptions?on_conflict=owner_id', {
    method: 'POST',
    headers: { Prefer: 'resolution=merge-duplicates,return=representation' },
    body: JSON.stringify(row),
  });
}

export default { fetch: (req) => handle(req, { env: readEnv() }) };

function readEnv() {
  // eslint-disable-next-line no-undef
  if (typeof Deno !== 'undefined') return Deno.env.toObject();
  return globalThis.process?.env ?? {};
}
