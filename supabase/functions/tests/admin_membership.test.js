import assert from 'node:assert/strict';
import test from 'node:test';

import { handle as grant } from '../admin-membership/index.js';

const ENV = {
  SUPABASE_URL: 'https://x.test',
  SUPABASE_SERVICE_ROLE_KEY: 'service-key',
};
const USER = '11111111-1111-1111-1111-111111111111';
const OTHER = '22222222-2222-2222-2222-222222222222';

function token(sub) {
  return `h.${Buffer.from(JSON.stringify({ sub })).toString('base64url')}.s`;
}

/** PostgREST, recorded. */
function world({ admin = true, emails = {} } = {}) {
  const calls = [];
  const fetch = async (url, init = {}) => {
    const target = String(url);
    calls.push({ url: target, init, body: init.body ? JSON.parse(init.body) : null });

    if (target.includes('/profiles') && target.includes('select=is_admin')) {
      return new Response(JSON.stringify([{ is_admin: admin }]), { status: 200 });
    }
    if (target.includes('/profiles') && target.includes('select=id')) {
      const match = /email=eq\.([^&]+)/.exec(target);
      const found = emails[decodeURIComponent(match?.[1] ?? '')];
      return new Response(JSON.stringify(found ? [{ id: found }] : []), { status: 200 });
    }
    return new Response('', { status: 201 });
  };
  return { calls, fetch };
}

function request(body, sub = USER) {
  return new Request('https://x.test/functions/v1/admin-membership', {
    method: 'POST',
    headers: { Authorization: `Bearer ${token(sub)}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
}

const wrote = (calls) => calls.find((c) => c.url.includes('/subscriptions'));

test('an admin can grant themselves a membership', async () => {
  const w = world();
  const response = await grant(
    request({ status: 'active', plan: 'founder', ceilingMicros: 25_000_000 }),
    { env: ENV, fetch: w.fetch },
  );

  assert.equal(response.status, 200);
  const row = wrote(w.calls).body;
  assert.equal(row.owner_id, USER);
  assert.equal(row.status, 'active');
  assert.equal(row.spend_ceiling_micros, 25_000_000);
});

test('a non-admin is refused, and nothing is written', async () => {
  // The rule `0004` set: a client cannot grant itself a membership. This
  // endpoint must not become the exception to it.
  const w = world({ admin: false });
  const response = await grant(request({ ceilingMicros: 1_000_000 }), {
    env: ENV,
    fetch: w.fetch,
  });

  assert.equal(response.status, 403);
  assert.equal(await response.text(), JSON.stringify({ message: 'Not allowed.' }));
  assert.equal(wrote(w.calls), undefined);
});

test('a signed-out caller never reaches the admin check', async () => {
  const w = world();
  const response = await grant(
    new Request('https://x.test/functions/v1/admin-membership', {
      method: 'POST',
      body: '{}',
    }),
    { env: ENV, fetch: w.fetch },
  );

  assert.equal(response.status, 401);
  assert.equal(w.calls.length, 0);
});

test('a ceiling above the cap is refused rather than clamped', async () => {
  // Clamping would silently grant something other than what was typed, and
  // the number is the whole point of the field.
  const w = world();
  const response = await grant(request({ ceilingMicros: 999_000_000 }), {
    env: ENV,
    fetch: w.fetch,
  });

  assert.equal(response.status, 400);
  assert.equal(wrote(w.calls), undefined);
});

test('a negative or non-numeric ceiling is refused', async () => {
  // `NaN` is deliberately not in this list: JSON has no way to carry it, so a
  // client sending one transmits `null`, which reads as "no ceiling" — and a
  // ceiling of zero is a real state, not a malformed one. Testing it here
  // would have been testing the JSON encoder.
  for (const ceilingMicros of [-1, '-50', 'lots']) {
    const w = world();
    const response = await grant(request({ ceilingMicros }), {
      env: ENV,
      fetch: w.fetch,
    });
    assert.equal(response.status, 400, `accepted ${ceilingMicros}`);
    assert.equal(wrote(w.calls), undefined);
  }
});

test('an active plan with a zero ceiling is allowed, and spends nothing',
    async () => {
  // Coherent rather than broken: `within_ceiling` needs spend *below* the
  // ceiling, so this is an account that is a member and has no managed
  // allowance. Refusing it would make "suspend their spend" impossible
  // without cancelling them.
  const w = world();
  const response = await grant(request({ status: 'active', ceilingMicros: 0 }), {
    env: ENV,
    fetch: w.fetch,
  });

  assert.equal(response.status, 200);
  assert.equal(wrote(w.calls).body.spend_ceiling_micros, 0);
});

test('past_due cannot be set by hand — it belongs to Stripe', async () => {
  const w = world();
  const response = await grant(request({ status: 'past_due' }), {
    env: ENV,
    fetch: w.fetch,
  });
  assert.equal(response.status, 400);
  assert.equal(wrote(w.calls), undefined);
});

test('another account can be granted by address', async () => {
  const w = world({ emails: { 'someone@test': OTHER } });
  const response = await grant(
    request({ email: 'Someone@Test', status: 'active', ceilingMicros: 5_000_000 }),
    { env: ENV, fetch: w.fetch },
  );

  assert.equal(response.status, 200);
  assert.equal(wrote(w.calls).body.owner_id, OTHER);
});

test('an address with no account says so, rather than granting the caller',
    async () => {
  // The bug worth guarding: falling back to `ctx.userId` on a typo would comp
  // the admin instead of the person they meant.
  const w = world();
  const response = await grant(request({ email: 'nobody@test' }), {
    env: ENV,
    fetch: w.fetch,
  });

  assert.equal(response.status, 404);
  assert.equal(wrote(w.calls), undefined);
});
