// The billing path, tested without Stripe.
//
//   node --test supabase/functions/tests/stripe.test.js
//
// A webhook endpoint that does not verify signatures is a public endpoint
// anyone can POST "this account is now a paying member" to, so most of what is
// below is about the ways verification can be got wrong rather than about the
// happy path.

import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  ceilingFor,
  statusFor,
  timingSafeEqual,
  verifyStripeSignature,
} from '../_shared/stripe.js';
import { handle as webhook } from '../stripe-webhook/index.js';

const SECRET = 'whsec_test_secret';
const ENV = {
  SHIFT_STRIPE_WEBHOOK_SECRET: SECRET,
  SUPABASE_URL: 'https://x.test',
  SUPABASE_SERVICE_ROLE_KEY: 'service-key',
};

async function sign(payload, secret = SECRET, timestamp = Math.floor(Date.now() / 1000)) {
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const bytes = new Uint8Array(
    await crypto.subtle.sign(
      'HMAC',
      key,
      new TextEncoder().encode(`${timestamp}.${payload}`),
    ),
  );
  let hex = '';
  for (const byte of bytes) hex += byte.toString(16).padStart(2, '0');
  return `t=${timestamp},v1=${hex}`;
}

function recordingFetch(rows = [{ owner_id: 'u1' }]) {
  const calls = [];
  const fetch = async (url, init) => {
    calls.push({ url, init, body: init?.body ? JSON.parse(init.body) : null });
    return new Response(JSON.stringify(rows), { status: 200 });
  };
  return { calls, fetch };
}

function event(type, object) {
  return JSON.stringify({ type, data: { object } });
}

// -------------------------------------------------------------- signatures

test('a correctly signed payload verifies', async () => {
  const payload = event('customer.subscription.updated', { customer: 'cus_1' });
  const parsed = await verifyStripeSignature(payload, await sign(payload), SECRET);
  assert.equal(parsed.type, 'customer.subscription.updated');
});

test('a payload signed with the wrong secret is rejected', async () => {
  const payload = event('customer.subscription.updated', { customer: 'cus_1' });
  const header = await sign(payload, 'whsec_someone_elses');
  await assert.rejects(
    () => verifyStripeSignature(payload, header, SECRET),
    /does not match/,
  );
});

test('a tampered payload is rejected even with a valid-looking header',
  async () => {
    // The whole attack: keep the signature, change the amount.
    const original = event('customer.subscription.updated', { customer: 'cus_1' });
    const header = await sign(original);
    const tampered = event('customer.subscription.updated', { customer: 'cus_attacker' });

    await assert.rejects(
      () => verifyStripeSignature(tampered, header, SECRET),
      /does not match/,
    );
  });

test('an old signature is rejected, so one capture cannot be replayed forever',
  async () => {
    const payload = event('customer.subscription.updated', { customer: 'cus_1' });
    const old = Math.floor(Date.now() / 1000) - 3600;
    const header = await sign(payload, SECRET, old);

    await assert.rejects(
      () => verifyStripeSignature(payload, header, SECRET),
      /tolerance/,
    );
  });

test('a signature from the future is rejected too — a skewed clock is not a '
  + 'reason to trust one', async () => {
  const payload = event('customer.subscription.updated', { customer: 'cus_1' });
  const ahead = Math.floor(Date.now() / 1000) + 3600;
  const header = await sign(payload, SECRET, ahead);

  await assert.rejects(
    () => verifyStripeSignature(payload, header, SECRET),
    /tolerance/,
  );
});

test('a missing or malformed header is rejected', async () => {
  const payload = event('customer.subscription.updated', { customer: 'cus_1' });
  await assert.rejects(() => verifyStripeSignature(payload, null, SECRET), /Missing/);
  await assert.rejects(
    () => verifyStripeSignature(payload, 'nonsense', SECRET),
    /Malformed/,
  );
});

test('an unset webhook secret refuses rather than accepting everything',
  async () => {
    const payload = event('customer.subscription.updated', { customer: 'cus_1' });
    const header = await sign(payload);
    await assert.rejects(
      () => verifyStripeSignature(payload, header, ''),
      /not set/,
    );
  });

test('several v1 signatures verify if any matches, which is what a secret '
  + 'rotation looks like', async () => {
  const payload = event('customer.subscription.updated', { customer: 'cus_1' });
  const good = await sign(payload);
  const timestamp = good.split(',')[0].slice(2);
  const combined = `${good},v1=${'0'.repeat(64)}`;

  const parsed = await verifyStripeSignature(payload, combined, SECRET);
  assert.equal(parsed.type, 'customer.subscription.updated');
  assert.ok(timestamp.length > 0);
});

test('timingSafeEqual is correct as well as constant-ish', () => {
  assert.equal(timingSafeEqual('abc', 'abc'), true);
  assert.equal(timingSafeEqual('abc', 'abd'), false);
  assert.equal(timingSafeEqual('abc', 'abcd'), false);
  assert.equal(timingSafeEqual('', ''), true);
});

// ------------------------------------------------------------- entitlement

test('unknown Stripe statuses mean "not entitled", not "probably fine"', () => {
  assert.equal(statusFor('active'), 'active');
  assert.equal(statusFor('trialing'), 'trialing');
  assert.equal(statusFor('past_due'), 'past_due');
  assert.equal(statusFor('unpaid'), 'past_due');
  assert.equal(statusFor('canceled'), 'canceled');
  assert.equal(statusFor('incomplete'), 'none');
  assert.equal(statusFor('something_stripe_adds_in_2027'), 'none');
});

test('a plan with no ceiling defined gets zero, so forgetting one fails closed',
  () => {
    assert.equal(ceilingFor('pro'), 25_000_000);
    assert.equal(ceilingFor('unheard-of'), 0);
    assert.equal(ceilingFor(undefined), 0);
  });

// ---------------------------------------------------------------- endpoint

test('a forged webhook is refused without touching the database', async () => {
  const { calls, fetch } = recordingFetch();
  const payload = event('customer.subscription.updated', {
    customer: 'cus_1',
    status: 'active',
  });

  const response = await webhook(
    new Request('https://x.test/stripe-webhook', {
      method: 'POST',
      headers: { 'Stripe-Signature': await sign(payload, 'wrong-secret') },
      body: payload,
    }),
    { env: ENV, fetch },
  );

  assert.equal(response.status, 400);
  assert.equal(calls.length, 0, 'nothing was written');
});

test('a signed subscription update writes the status and its ceiling',
  async () => {
    const { calls, fetch } = recordingFetch();
    const payload = event('customer.subscription.updated', {
      id: 'sub_1',
      customer: 'cus_1',
      status: 'active',
      metadata: { plan: 'pro' },
      current_period_end: 1790000000,
    });

    const response = await webhook(
      new Request('https://x.test/stripe-webhook', {
        method: 'POST',
        headers: { 'Stripe-Signature': await sign(payload) },
        body: payload,
      }),
      { env: ENV, fetch },
    );

    assert.equal(response.status, 200);
    assert.equal(calls.length, 1);
    assert.ok(calls[0].url.includes('stripe_customer_id=eq.cus_1'));
    assert.equal(calls[0].body.status, 'active');
    assert.equal(calls[0].body.spend_ceiling_micros, 25_000_000);
    assert.equal(calls[0].body.stripe_subscription_id, 'sub_1');
  });

test('a cancellation zeroes the ceiling as well as the status, so a stale '
  + 'read still cannot spend', async () => {
  const { calls, fetch } = recordingFetch();
  const payload = event('customer.subscription.deleted', {
    id: 'sub_1',
    customer: 'cus_1',
    status: 'canceled',
    metadata: { plan: 'pro' },
  });

  await webhook(
    new Request('https://x.test/stripe-webhook', {
      method: 'POST',
      headers: { 'Stripe-Signature': await sign(payload) },
      body: payload,
    }),
    { env: ENV, fetch },
  );

  assert.equal(calls[0].body.status, 'canceled');
  assert.equal(calls[0].body.spend_ceiling_micros, 0);
});

test('checkout ties the customer to the account we named, never to one the '
  + 'payload invents', async () => {
  const { calls, fetch } = recordingFetch();
  const payload = event('checkout.session.completed', {
    customer: 'cus_1',
    subscription: 'sub_1',
    client_reference_id: 'u1',
    metadata: { plan: 'starter' },
  });

  await webhook(
    new Request('https://x.test/stripe-webhook', {
      method: 'POST',
      headers: { 'Stripe-Signature': await sign(payload) },
      body: payload,
    }),
    { env: ENV, fetch },
  );

  assert.equal(calls[0].body.owner_id, 'u1');
  assert.equal(calls[0].body.stripe_customer_id, 'cus_1');
  assert.equal(calls[0].body.spend_ceiling_micros, 5_000_000);
});

test('a checkout with no account reference is ignored rather than guessed at',
  async () => {
    const { calls, fetch } = recordingFetch();
    const payload = event('checkout.session.completed', { customer: 'cus_1' });

    const response = await webhook(
      new Request('https://x.test/stripe-webhook', {
        method: 'POST',
        headers: { 'Stripe-Signature': await sign(payload) },
        body: payload,
      }),
      { env: ENV, fetch },
    );

    assert.equal(response.status, 200);
    assert.equal(calls.length, 0);
  });

test('an event we do not handle is acknowledged, not failed — Stripe retries '
  + 'anything that is not 2xx', async () => {
  const { calls, fetch } = recordingFetch();
  const payload = event('invoice.payment_succeeded', { customer: 'cus_1' });

  const response = await webhook(
    new Request('https://x.test/stripe-webhook', {
      method: 'POST',
      headers: { 'Stripe-Signature': await sign(payload) },
      body: payload,
    }),
    { env: ENV, fetch },
  );

  assert.equal(response.status, 200);
  assert.equal(calls.length, 0);
});

test('an event for a customer we have never seen is acknowledged, not retried '
  + 'forever', async () => {
  const { fetch } = recordingFetch([]);
  const payload = event('customer.subscription.updated', {
    customer: 'cus_unknown',
    status: 'active',
  });

  const response = await webhook(
    new Request('https://x.test/stripe-webhook', {
      method: 'POST',
      headers: { 'Stripe-Signature': await sign(payload) },
      body: payload,
    }),
    { env: ENV, fetch },
  );

  assert.equal(response.status, 200);
  assert.equal((await response.json()).ignored, 'unknown customer');
});
