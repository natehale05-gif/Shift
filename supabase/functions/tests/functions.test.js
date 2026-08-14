// Runs on Node 22 and on Deno unchanged, because the handlers are written
// against Request/Response/WebCrypto and nothing else.
//
//   node --test supabase/functions/tests/
//
// This is the whole verification story for the server side right now: there is
// no Supabase project to deploy to yet, so every assertion here is against the
// handler in-process with a fake fetch. What that cannot cover is stated in the
// PR rather than implied — nothing below proves the function *deploys*.

import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  bytesToHex,
  hexToBytes,
  lastFour,
  masterKeyBytes,
  open,
  seal,
} from '../_shared/crypto.js';
import { problem, subjectOf, withAdapter } from '../_shared/handler.js';
import { handle as providerKey } from '../provider-key/index.js';

const KEY_B64 = Buffer.from(new Uint8Array(32).fill(7)).toString('base64');
const ENV = {
  SHIFT_KMS_KEY: KEY_B64,
  SHIFT_KMS_KEY_ID: 'kms-test',
  SUPABASE_URL: 'https://x.test',
  SUPABASE_SERVICE_ROLE_KEY: 'service-key',
};

/** A JWT-shaped token. Unsigned on purpose — see `subjectOf`. */
function token(sub) {
  const payload = Buffer.from(JSON.stringify({ sub }))
    .toString('base64url');
  return `header.${payload}.signature`;
}

const USER = '11111111-1111-1111-1111-111111111111';

/** Records what the handler sent to PostgREST. */
function recordingFetch(response) {
  const calls = [];
  const fetch = async (url, init) => {
    calls.push({ url, init, body: init?.body ? JSON.parse(init.body) : null });
    return response ?? new Response(JSON.stringify([{ id: 'k1', last_four: 'wxyz' }]), { status: 200 });
  };
  return { calls, fetch };
}

// ------------------------------------------------------------------ crypto

test('a sealed secret round-trips', async () => {
  const key = masterKeyBytes(ENV);
  const sealed = await seal('sk-ant-secret-value', key);
  assert.equal(await open(sealed, key), 'sk-ant-secret-value');
});

test('the ciphertext does not contain the plaintext', async () => {
  const sealed = await seal('sk-ant-secret-value', masterKeyBytes(ENV));
  assert.ok(!Buffer.from(sealed).includes('secret'));
});

test('two seals of the same secret differ — a fresh IV each time', async () => {
  // Otherwise identical keys are identifiable in the table, which tells an
  // attacker which accounts share a key without decrypting anything.
  const key = masterKeyBytes(ENV);
  const a = await seal('sk-same', key);
  const b = await seal('sk-same', key);
  assert.notEqual(bytesToHex(a), bytesToHex(b));
  assert.equal(await open(a, key), await open(b, key));
});

test('a tampered record fails to decrypt rather than decrypting to garbage',
  async () => {
    const key = masterKeyBytes(ENV);
    const sealed = await seal('sk-ant-secret-value', key);
    sealed[sealed.length - 1] ^= 0xff;
    await assert.rejects(() => open(sealed, key));
  });

test('the wrong master key cannot read a record', async () => {
  const sealed = await seal('sk-ant-secret-value', masterKeyBytes(ENV));
  const other = new Uint8Array(32).fill(9);
  await assert.rejects(() => open(sealed, other));
});

test('a truncated record is rejected before decryption is attempted',
  async () => {
    await assert.rejects(
      () => open(new Uint8Array(4), masterKeyBytes(ENV)),
      /truncated/,
    );
  });

test('a missing master key refuses to start rather than defaulting', () => {
  // A vault that silently encrypts under a predictable key looks fine until
  // somebody reads the table.
  assert.throws(() => masterKeyBytes({}), /SHIFT_KMS_KEY/);
  assert.throws(
    () => masterKeyBytes({ SHIFT_KMS_KEY: Buffer.from('short').toString('base64') }),
    /32 bytes/,
  );
});

test('a master key pasted with stray whitespace still works', async () => {
  // This value is typed in by a human, often on a phone, and a trailing
  // newline is invisible in every UI that displays it — but `atob` rejects it.
  // Without this the vault fails on every single call, with an error naming
  // the key and explaining nothing.
  const clean = Buffer.from(new Uint8Array(32).fill(7)).toString('base64');

  for (const messy of [`${clean}\n`, ` ${clean} `, `${clean}\r\n`, `${clean}\t`]) {
    assert.deepEqual(
      masterKeyBytes({ SHIFT_KMS_KEY: messy }),
      masterKeyBytes({ SHIFT_KMS_KEY: clean }),
      `whitespace variant ${JSON.stringify(messy.slice(-3))} should decode the same`,
    );
  }

  // …and a key stored one way still opens a record sealed the other way,
  // which is what matters if the secret is ever re-pasted.
  const sealed = await seal('sk-ant-abcdwxyz', masterKeyBytes({ SHIFT_KMS_KEY: clean }));
  assert.equal(
    await open(sealed, masterKeyBytes({ SHIFT_KMS_KEY: `${clean}\n` })),
    'sk-ant-abcdwxyz',
  );
});

test('a mistyped master key says what is wrong with it', () => {
  // "not valid base64" and "decoded to the wrong length" are different
  // mistakes with different fixes, and the person reading the log is the
  // person who pasted it.
  assert.throws(
    () => masterKeyBytes({ SHIFT_KMS_KEY: 'this is definitely not base64!!' }),
    /base64|32 bytes/,
  );
  assert.throws(
    () => masterKeyBytes({
      SHIFT_KMS_KEY: Buffer.from(new Uint8Array(16)).toString('base64'),
    }),
    /got 16/,
  );
});

test('hex encoding survives a round trip, since bytea travels as hex', () => {
  const bytes = new Uint8Array([0, 1, 15, 16, 255]);
  assert.deepEqual(hexToBytes(bytesToHex(bytes)), bytes);
});

test('lastFour masks a secret too short to show any of', () => {
  assert.equal(lastFour('sk-ant-abcdwxyz'), 'wxyz');
  assert.equal(lastFour('short'), '••••');
});

// ----------------------------------------------------------------- adapter

test('a request with no token is refused before the handler runs', async () => {
  let ran = false;
  const guarded = withAdapter(async () => {
    ran = true;
    return new Response('ok');
  });

  const response = await guarded(new Request('https://x.test/', { method: 'POST' }), { env: ENV });

  assert.equal(response.status, 401);
  assert.equal(ran, false);
});

test('subjectOf reads the claim, and returns null for anything odd', () => {
  assert.equal(subjectOf(`Bearer ${token(USER)}`), USER);
  assert.equal(subjectOf(null), null);
  assert.equal(subjectOf('Basic abc'), null);
  assert.equal(subjectOf('Bearer not-a-jwt'), null);
  assert.equal(subjectOf(`Bearer ${token('')}`), null);
});

test('a handler that throws returns 500 without echoing the error', async () => {
  // These handlers hold decryption keys and provider secrets. An exception
  // message is exactly the sort of thing that quotes one back.
  const boom = withAdapter(async () => {
    throw new Error('SHIFT_KMS_KEY is aaaabbbbcccc');
  }, { requireAuth: false });

  const response = await boom(new Request('https://x.test/', { method: 'POST' }), { env: ENV });
  const body = await response.json();

  assert.equal(response.status, 500);
  assert.ok(!JSON.stringify(body).includes('aaaabbbbcccc'));
});

test('a preflight is answered without auth', async () => {
  const guarded = withAdapter(async () => new Response('ok'));
  const response = await guarded(
    new Request('https://x.test/', { method: 'OPTIONS' }), { env: ENV });
  assert.equal(response.status, 204);
  assert.equal(response.headers.get('Access-Control-Allow-Origin'), '*');
});

test('a preflight allows the headers the provider actually needs', async () => {
  // The bug this pins, and it was invisible from the server side: the allow
  // list was `authorization, apikey, content-type`, which is exactly the set
  // the Setup card's test call sends. So "Run test" passed while every real
  // turn failed — Anthropic's client sends `anthropic-version` on every
  // request, the preflight refused it, and the browser reports a blocked
  // preflight as no answer at all. The app said "could not reach the
  // provider", about a provider it was never allowed to ask.
  const guarded = withAdapter(async () => new Response('ok'));
  const response = await guarded(
    new Request('https://x.test/', {
      method: 'OPTIONS',
      headers: {
        'Access-Control-Request-Headers':
          'authorization, apikey, content-type, anthropic-version',
      },
    }),
    { env: ENV },
  );

  assert.equal(response.status, 204);
  assert.match(
    response.headers.get('Access-Control-Allow-Headers'),
    /anthropic-version/,
  );
});

test('a preflight that asks for nothing still gets the defaults', async () => {
  const guarded = withAdapter(async () => new Response('ok'));
  const response = await guarded(
    new Request('https://x.test/', { method: 'OPTIONS' }), { env: ENV });

  assert.match(response.headers.get('Access-Control-Allow-Headers'),
    /authorization/);
});

test('a preflight is cached, so a turn is not two round trips', async () => {
  const guarded = withAdapter(async () => new Response('ok'));
  const response = await guarded(
    new Request('https://x.test/', { method: 'OPTIONS' }), { env: ENV });

  assert.ok(Number(response.headers.get('Access-Control-Max-Age')) > 0);
});

test('problem() shapes the body the client already knows how to read', async () => {
  const body = await problem(429, 'ceiling reached').json();
  assert.equal(body.message, 'ceiling reached');
});

// ------------------------------------------------------------ provider-key

test('a key is encrypted before it reaches the database', async () => {
  const { calls, fetch } = recordingFetch();

  await providerKey(
    new Request('https://x.test/provider-key', {
      method: 'POST',
      headers: { Authorization: `Bearer ${token(USER)}` },
      body: JSON.stringify({ provider: 'anthropic', secret: 'sk-ant-abcdwxyz' }),
    }),
    { env: ENV, fetch },
  );

  const written = calls[0].body;
  assert.equal(written.owner_id, USER);
  assert.equal(written.provider, 'anthropic');
  assert.equal(written.key_owner, 'user');
  assert.equal(written.last_four, 'wxyz');
  assert.equal(written.kms_key_id, 'kms-test');
  assert.ok(!JSON.stringify(written).includes('sk-ant-abcdwxyz'),
    'the plaintext key must never appear in the row');

  // …and it is the real key underneath, not something merely unreadable.
  const stored = hexToBytes(written.ciphertext);
  assert.equal(await open(stored, masterKeyBytes(ENV)), 'sk-ant-abcdwxyz');
});

test('the response carries metadata and never the secret', async () => {
  const { fetch } = recordingFetch();

  const response = await providerKey(
    new Request('https://x.test/provider-key', {
      method: 'POST',
      headers: { Authorization: `Bearer ${token(USER)}` },
      body: JSON.stringify({ provider: 'anthropic', secret: 'sk-ant-abcdwxyz' }),
    }),
    { env: ENV, fetch },
  );
  const body = await response.json();

  assert.equal(body.last_four, 'wxyz');
  assert.ok(!JSON.stringify(body).includes('sk-ant-abcdwxyz'));
});

test('whitespace inside a pasted key is stripped, not just trimmed',
  async () => {
    // A key copied out of an email arrives with line breaks in the middle.
    // Storing those sends a 401 the user cannot explain, and the app blames
    // the key — the exact defect F3 fixed on the client.
    const { calls, fetch } = recordingFetch();

    await providerKey(
      new Request('https://x.test/provider-key', {
        method: 'POST',
        headers: { Authorization: `Bearer ${token(USER)}` },
        body: JSON.stringify({ provider: 'anthropic', secret: ' sk-ant\n-abcd\r\nwxyz ' }),
      }),
      { env: ENV, fetch },
    );

    const stored = hexToBytes(calls[0].body.ciphertext);
    assert.equal(await open(stored, masterKeyBytes(ENV)), 'sk-ant-abcdwxyz');
  });

test('an unknown provider is rejected without touching the database',
  async () => {
    const { calls, fetch } = recordingFetch();

    const response = await providerKey(
      new Request('https://x.test/provider-key', {
        method: 'POST',
        headers: { Authorization: `Bearer ${token(USER)}` },
        body: JSON.stringify({ provider: 'definitely-not-real', secret: 'sk-abcdwxyz' }),
      }),
      { env: ENV, fetch },
    );

    assert.equal(response.status, 400);
    assert.equal(calls.length, 0);
  });

test('a secret too short to be a key is rejected', async () => {
  const { calls, fetch } = recordingFetch();

  const response = await providerKey(
    new Request('https://x.test/provider-key', {
      method: 'POST',
      headers: { Authorization: `Bearer ${token(USER)}` },
      body: JSON.stringify({ provider: 'anthropic', secret: 'sk-1' }),
    }),
    { env: ENV, fetch },
  );

  assert.equal(response.status, 400);
  assert.equal(calls.length, 0);
});

test('the row is written for the caller, never for an id in the body',
  async () => {
    // The obvious way to break a vault: ask it to store a key under somebody
    // else's account. `owner_id` comes from the token, and the body's is
    // ignored.
    const { calls, fetch } = recordingFetch();

    await providerKey(
      new Request('https://x.test/provider-key', {
        method: 'POST',
        headers: { Authorization: `Bearer ${token(USER)}` },
        body: JSON.stringify({
          provider: 'anthropic',
          secret: 'sk-ant-abcdwxyz',
          owner_id: '22222222-2222-2222-2222-222222222222',
        }),
      }),
      { env: ENV, fetch },
    );

    assert.equal(calls[0].body.owner_id, USER);
  });

test('storing a key upserts, so rotating one never leaves an account with none',
  async () => {
    const { calls, fetch } = recordingFetch();

    await providerKey(
      new Request('https://x.test/provider-key', {
        method: 'POST',
        headers: { Authorization: `Bearer ${token(USER)}` },
        body: JSON.stringify({ provider: 'anthropic', secret: 'sk-ant-abcdwxyz' }),
      }),
      { env: ENV, fetch },
    );

    assert.ok(calls[0].url.includes('on_conflict=owner_id,provider,key_owner'));
    assert.ok(calls[0].init.headers.Prefer.includes('merge-duplicates'));
  });

test('a GET is refused — this endpoint only ever takes a secret in',
  async () => {
    const { calls, fetch } = recordingFetch();

    const response = await providerKey(
      new Request('https://x.test/provider-key', {
        method: 'GET',
        headers: { Authorization: `Bearer ${token(USER)}` },
      }),
      { env: ENV, fetch },
    );

    assert.equal(response.status, 405);
    assert.equal(calls.length, 0);
  });

// ------------------------------------------------- platform (SHIFT's) keys

/** A fetch that answers the admin lookup and records the write. */
function adminFetch({ admin }) {
  const calls = [];
  const fetch = async (url, init) => {
    calls.push({ url, init, body: init?.body ? JSON.parse(init.body) : null });
    if (url.includes('/profiles?')) {
      return new Response(JSON.stringify([{ is_admin: admin }]), { status: 200 });
    }
    return new Response(
      JSON.stringify([{ id: 'p1', last_four: 'wxyz' }]),
      { status: 200 },
    );
  };
  return { calls, fetch };
}

function platformRequest(secret = 'sk-ant-abcdwxyz') {
  return new Request('https://x.test/provider-key', {
    method: 'POST',
    headers: { Authorization: `Bearer ${token(USER)}` },
    body: JSON.stringify({ provider: 'anthropic', secret, scope: 'platform' }),
  });
}

test('an admin can store a platform key, encrypted', async () => {
  const { calls, fetch } = adminFetch({ admin: true });

  const response = await providerKey(platformRequest(), { env: ENV, fetch });
  const body = await response.json();

  assert.equal(response.status, 200);
  assert.equal(body.scope, 'platform');

  const write = calls.find((c) => c.url.includes('/platform_keys'));
  assert.ok(write, 'it wrote to platform_keys, not provider_keys');
  assert.ok(!('owner_id' in write.body),
    'a platform key belongs to no account — that was the schema bug');
  assert.ok(!JSON.stringify(write.body).includes('sk-ant-abcdwxyz'));
  assert.equal(
    await open(hexToBytes(write.body.ciphertext), masterKeyBytes(ENV)),
    'sk-ant-abcdwxyz',
  );
});

test('a non-admin is refused and nothing is written', async () => {
  const { calls, fetch } = adminFetch({ admin: false });

  const response = await providerKey(platformRequest(), { env: ENV, fetch });

  assert.equal(response.status, 403);
  assert.ok(!calls.some((c) => c.url.includes('/platform_keys')),
    'the refusal happens before any write');
});

test('the refusal says nothing about why', async () => {
  // Telling someone who guessed at this that they merely lack a flag confirms
  // the scope exists and is worth attacking.
  const { fetch } = adminFetch({ admin: false });
  const body = await (await providerKey(platformRequest(), { env: ENV, fetch })).json();
  assert.ok(!/admin/i.test(JSON.stringify(body)));
});

test('admin is read from the database, not believed from the token', async () => {
  // A JWT claim is whatever the issuer put in it, and admin should not ride in
  // a token that lives for an hour on a device. Revoking it must take effect
  // on the next request.
  const { calls, fetch } = adminFetch({ admin: true });
  await providerKey(platformRequest(), { env: ENV, fetch });

  const lookup = calls.find((c) => c.url.includes('/profiles?'));
  assert.ok(lookup, 'it checked the profiles row');
  assert.ok(lookup.url.includes(`id=eq.${USER}`), 'for the caller');
  assert.ok(lookup.url.includes('select=is_admin'));
});

test('storing a platform key upserts on provider, so there is one per '
  + 'provider and re-posting rotates it', async () => {
  const { calls, fetch } = adminFetch({ admin: true });
  await providerKey(platformRequest(), { env: ENV, fetch });

  const write = calls.find((c) => c.url.includes('/platform_keys'));
  assert.ok(write.url.includes('on_conflict=provider'));
  assert.ok(write.init.headers.Prefer.includes('merge-duplicates'));
  assert.equal(write.body.enabled, true,
    're-pasting a key re-enables a provider that was switched off');
});

test('an unknown provider is refused even for an admin, before the admin '
  + 'lookup', async () => {
  const { calls, fetch } = adminFetch({ admin: true });

  const response = await providerKey(
    new Request('https://x.test/provider-key', {
      method: 'POST',
      headers: { Authorization: `Bearer ${token(USER)}` },
      body: JSON.stringify({
        provider: 'not-a-provider',
        secret: 'sk-abcdwxyz',
        scope: 'platform',
      }),
    }),
    { env: ENV, fetch },
  );

  assert.equal(response.status, 400);
  assert.equal(calls.length, 0);
});

test('scope defaults to the caller own key, never the platform', async () => {
  // A missing or unrecognised scope must not accidentally reach the shared
  // keys.
  const { calls, fetch } = adminFetch({ admin: true });

  for (const scope of [undefined, 'PLATFORM', 'shared', '', null]) {
    calls.length = 0;
    await providerKey(
      new Request('https://x.test/provider-key', {
        method: 'POST',
        headers: { Authorization: `Bearer ${token(USER)}` },
        body: JSON.stringify({
          provider: 'anthropic',
          secret: 'sk-ant-abcdwxyz',
          scope,
        }),
      }),
      { env: ENV, fetch },
    );
    assert.ok(
      calls.some((c) => c.url.includes('/provider_keys')),
      `scope ${JSON.stringify(scope)} should be treated as a user key`,
    );
    assert.ok(!calls.some((c) => c.url.includes('/platform_keys')));
  }
});
