import assert from 'node:assert/strict';
import test from 'node:test';

import { costMicros, rateFor, UNREPORTED_CALL_MICROS } from '../_shared/pricing.js';
import {
  parseProxyPath,
  proxyableProviders,
  upstreamHeaders,
  upstreamUrl,
} from '../_shared/upstream.js';
import { meteredBody, UsageMeter } from '../_shared/usage_meter.js';

test('the path names a provider and a path, and nothing else', () => {
  assert.deepEqual(
    parseProxyPath('/functions/v1/provider-proxy/anthropic/v1/messages'),
    { provider: 'anthropic', path: '/v1/messages' },
  );
  // No provider segment, no path segment, or neither.
  for (const bad of [
    '/functions/v1/provider-proxy/anthropic',
    '/functions/v1/provider-proxy//v1/messages',
    '/functions/v1/something-else/anthropic/v1/messages',
  ]) {
    assert.equal(parseProxyPath(bad).provider, null, bad);
  }
});

test('the host is ours to choose, never the caller\'s', () => {
  // The whole reason the table exists. If any of these produced a URL, this
  // endpoint would be an open relay holding SHIFT's provider keys.
  assert.equal(upstreamUrl('anthropic', '/../evil.example/v1/messages'), null);
  assert.equal(upstreamUrl('anthropic', '//evil.example/v1/messages'), null);
  assert.equal(upstreamUrl('anthropic', 'https://evil.example/v1/messages'), null);
  assert.equal(upstreamUrl('nope', '/v1/messages'), null);

  assert.equal(
    upstreamUrl('anthropic', '/v1/messages'),
    'https://api.anthropic.com/v1/messages',
  );
});

test('only the paths a member is actually buying are reachable', () => {
  // Our own provider account's administration lives on the same host.
  assert.equal(upstreamUrl('anthropic', '/v1/organizations/me'), null);
  assert.equal(upstreamUrl('openai', '/v1/organization/invites'), null);
  assert.equal(upstreamUrl('openai', '/v1/chat/completions').length > 0, true);
});

test('a caller cannot smuggle in its own credential as a query parameter', () => {
  const url = upstreamUrl('gemini', '/v1beta/models/x:streamGenerateContent',
      '?alt=sse&key=theirs');
  assert.ok(url.includes('alt=sse'));
  assert.ok(!url.includes('key=theirs'));
});

test('the session token is never forwarded to the provider', () => {
  // It authorises reads of this member's account. A third party must never
  // receive it — and a caller that pre-sets a provider key must not have it
  // survive either.
  const incoming = new Headers({
    Authorization: 'Bearer member-session-jwt',
    apikey: 'the-anon-key',
    'x-api-key': 'a-key-the-caller-chose',
    'anthropic-beta': 'code-execution-2025-05-22',
  });

  const sent = upstreamHeaders('anthropic', incoming, 'shifts-real-key');

  assert.equal(sent.get('x-api-key'), 'shifts-real-key');
  assert.equal(sent.get('apikey'), null);
  assert.equal(sent.get('authorization'), null);
  // Things the client legitimately chose still travel.
  assert.equal(sent.get('anthropic-beta'), 'code-execution-2025-05-22');
  assert.equal(sent.get('anthropic-version'), '2023-06-01');
});

test('every proxyable provider has a working route', () => {
  for (const provider of proxyableProviders()) {
    const headers = upstreamHeaders(provider, new Headers(), 'k');
    const authorized =
      headers.get('authorization') ||
      headers.get('x-api-key') ||
      headers.get('x-goog-api-key');
    assert.ok(authorized, `${provider} attaches no credential`);
  }
});

test('an unknown model is charged the most expensive rate, not nothing', () => {
  // The failure that costs real money. A model the table has not heard of
  // must not be free, or the ceiling never stops anyone.
  const unknown = costMicros({
    model: 'some-model-shipped-yesterday',
    inputTokens: 1_000_000,
    outputTokens: 1_000_000,
  });
  const known = costMicros({
    model: 'claude-haiku-4-5',
    inputTokens: 1_000_000,
    outputTokens: 1_000_000,
  });

  assert.ok(unknown > known);
  assert.ok(unknown >= 60_000_000);
});

test('a dated model id still finds its rate', () => {
  assert.deepEqual(rateFor('claude-sonnet-5-20260101'), rateFor('claude-sonnet-5'));
});

test('a call that reports nothing still costs something', () => {
  assert.ok(UNREPORTED_CALL_MICROS > 0);
});

test('a fractional cost rounds up, so small calls are never free', () => {
  assert.equal(costMicros({ model: 'claude-haiku-4-5', inputTokens: 1 }), 1);
});

test('Anthropic usage is read across the events it is split over', () => {
  const meter = new UsageMeter();
  meter.write('event: message_start\n');
  meter.write('data: {"type":"message_start","message":{"model":"claude-opus-4-8",' +
      '"usage":{"input_tokens":1200,"output_tokens":1}}}\n');
  meter.write('data: {"type":"content_block_delta"}\n');
  meter.write('data: {"type":"message_delta","usage":{"input_tokens":1200,' +
      '"output_tokens":800}}\n');
  meter.flush();

  assert.equal(meter.model, 'claude-opus-4-8');
  assert.equal(meter.inputTokens, 1200);
  // Repeated rather than summed: Anthropic restates the input on the final
  // delta, and summing double-charged every call.
  assert.equal(meter.outputTokens, 800);
});

test('OpenAI usage on the final chunk is read', () => {
  const meter = new UsageMeter();
  meter.write('data: {"model":"gpt-4o","choices":[{"delta":{"content":"hi"}}]}\n');
  meter.write('data: {"usage":{"prompt_tokens":30,"completion_tokens":70}}\n');
  meter.write('data: [DONE]\n');
  meter.flush();

  assert.equal(meter.inputTokens, 30);
  assert.equal(meter.outputTokens, 70);
});

test('Gemini reports a running total, so the last one wins', () => {
  const meter = new UsageMeter();
  meter.write('data: {"usageMetadata":{"promptTokenCount":10,' +
      '"candidatesTokenCount":5}}\n');
  meter.write('data: {"usageMetadata":{"promptTokenCount":10,' +
      '"candidatesTokenCount":90}}\n');
  meter.flush();

  assert.equal(meter.inputTokens, 10);
  assert.equal(meter.outputTokens, 90);
});

test('usage split across chunk boundaries is still counted', () => {
  // The bug this shape of code always has: a chunk can end mid-number, and a
  // half-parsed number is a wrong number.
  const meter = new UsageMeter();
  const payload =
      'data: {"type":"message_delta","usage":{"output_tokens":4321}}\n';
  for (let i = 0; i < payload.length; i += 7) {
    meter.write(payload.slice(i, i + 7));
  }
  meter.flush();

  assert.equal(meter.outputTokens, 4321);
});

test('a reply with no usage anywhere reports none, rather than guessing', () => {
  const meter = new UsageMeter();
  meter.write('data: {"choices":[{"delta":{"content":"hello"}}]}\n');
  meter.flush();
  assert.equal(meter.sawUsage, false);
});

test('the member\'s bytes pass through untouched, and metering still runs',
    async () => {
  const source = new ReadableStream({
    start(controller) {
      const encoder = new TextEncoder();
      controller.enqueue(encoder.encode('data: {"usage":{"prompt_tokens":5,'));
      controller.enqueue(encoder.encode('"completion_tokens":9}}\n'));
      controller.close();
    },
  });

  let recorded = null;
  const out = meteredBody(source, new UsageMeter(), (m) => { recorded = m; });

  const text = await new Response(out).text();
  assert.equal(text, 'data: {"usage":{"prompt_tokens":5,"completion_tokens":9}}\n');
  assert.equal(recorded.inputTokens, 5);
  assert.equal(recorded.outputTokens, 9);
});

test('a stream that ends early is still charged for what it used', async () => {
  // Someone closing the tab mid-reply already cost us the tokens.
  const source = new ReadableStream({
    start(controller) {
      controller.enqueue(
        new TextEncoder().encode('data: {"usage":{"prompt_tokens":11}}\n'),
      );
      controller.close();
    },
  });

  let recorded = null;
  const out = meteredBody(source, new UsageMeter(), (m) => { recorded = m; });
  await new Response(out).text();

  assert.equal(recorded.inputTokens, 11);
});

test('a response with no body at all is still recorded', async () => {
  let recorded = null;
  const out = meteredBody(null, new UsageMeter(), (m) => { recorded = m; });
  assert.equal(out, null);
  assert.notEqual(recorded, null);
  assert.equal(recorded.sawUsage, false);
});

// ------------------------------------------------------- the handler itself

import { seal, bytesToHex, masterKeyBytes } from '../_shared/crypto.js';
import { handle as proxy } from '../provider-proxy/index.js';

const ENV = {
  SHIFT_KMS_KEY: Buffer.from(new Uint8Array(32).fill(7)).toString('base64'),
  SHIFT_KMS_KEY_ID: 'kms-test',
  SUPABASE_URL: 'https://x.test',
  SUPABASE_SERVICE_ROLE_KEY: 'service-key',
};
const USER = '11111111-1111-1111-1111-111111111111';

function token(sub) {
  return `h.${Buffer.from(JSON.stringify({ sub })).toString('base64url')}.s`;
}

/** A stand-in for PostgREST and the provider, recording everything sent. */
async function fakeWorld({ entitled = true, hasKey = true, providerBody = '' } = {}) {
  const sealed = bytesToHex(await seal('sk-shift-real-key', masterKeyBytes(ENV)));
  const calls = [];

  const fetch = async (url, init = {}) => {
    calls.push({ url: String(url), init, headers: new Headers(init.headers ?? {}) });

    if (String(url).includes('/rpc/within_ceiling')) {
      return new Response(JSON.stringify(entitled), { status: 200 });
    }
    if (String(url).includes('/platform_keys')) {
      return new Response(
        JSON.stringify(hasKey ? [{ ciphertext: `\\x${sealed}` }] : []),
        { status: 200 },
      );
    }
    if (String(url).includes('/usage_events')) {
      return new Response('', { status: 201 });
    }
    // The provider.
    return new Response(providerBody, {
      status: 200,
      headers: { 'content-type': 'text/event-stream' },
    });
  };

  return { calls, fetch };
}

function proxyRequest(path, body = '{"model":"claude-opus-4-8","stream":true}') {
  return new Request(`https://x.test/functions/v1/provider-proxy${path}`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token(USER)}`, 'Content-Type': 'application/json' },
    body,
  });
}

test('an account that is not entitled is refused before any provider call',
    async () => {
  const world = await fakeWorld({ entitled: false });
  const response = await proxy(proxyRequest('/anthropic/v1/messages'),
      { env: ENV, fetch: world.fetch });

  assert.equal(response.status, 402);
  assert.ok(!world.calls.some((c) => c.url.includes('api.anthropic.com')),
      'the provider was called for an account that cannot pay');
  assert.ok(!world.calls.some((c) => c.url.includes('/platform_keys')),
      'the key was decrypted before entitlement was established');
});

test('an entitlement check that fails answers no', async () => {
  // A check that fails open is not a check.
  const fetch = async (url) => {
    if (String(url).includes('/rpc/within_ceiling')) throw new Error('down');
    return new Response('[]', { status: 200 });
  };
  const response = await proxy(proxyRequest('/anthropic/v1/messages'),
      { env: ENV, fetch });
  assert.equal(response.status, 402);
});

test('a signed-out caller never reaches the ceiling check', async () => {
  const world = await fakeWorld();
  const response = await proxy(
    new Request('https://x.test/functions/v1/provider-proxy/anthropic/v1/messages',
        { method: 'POST', body: '{}' }),
    { env: ENV, fetch: world.fetch },
  );
  assert.equal(response.status, 401);
  assert.equal(world.calls.length, 0);
});

test('an entitled call reaches the provider with SHIFT\'s key attached',
    async () => {
  const world = await fakeWorld({
    providerBody: 'data: {"type":"message_delta","usage":{"input_tokens":100,' +
        '"output_tokens":200}}\n',
  });
  const response = await proxy(proxyRequest('/anthropic/v1/messages'),
      { env: ENV, fetch: world.fetch });

  assert.equal(response.status, 200);
  const upstream = world.calls.find((c) => c.url.includes('api.anthropic.com'));
  assert.ok(upstream, 'the provider was never called');
  assert.equal(upstream.headers.get('x-api-key'), 'sk-shift-real-key');
  // The member's own token must not travel to a third party.
  assert.equal(upstream.headers.get('authorization'), null);
});

test('the reply streams back and the call is metered', async () => {
  const world = await fakeWorld({
    providerBody: 'data: {"type":"message_start","message":' +
        '{"model":"claude-haiku-4-5","usage":{"input_tokens":1000}}}\n' +
        'data: {"type":"message_delta","usage":{"output_tokens":2000}}\n',
  });
  const response = await proxy(proxyRequest('/anthropic/v1/messages'),
      { env: ENV, fetch: world.fetch });

  const text = await response.text();
  assert.ok(text.includes('message_delta'), 'the reply did not reach the member');

  // The usage insert is deliberately not awaited by the handler, so give the
  // floating promise a turn before asserting on it.
  await new Promise((resolve) => setTimeout(resolve, 10));

  const usage = world.calls.find((c) => c.url.includes('/usage_events'));
  assert.ok(usage, 'nothing was metered');
  const row = JSON.parse(usage.init.body);
  assert.equal(row.owner_id, USER);
  assert.equal(row.key_owner, 'managed');
  assert.equal(row.input_tokens, 1000);
  assert.equal(row.output_tokens, 2000);
  // Haiku is $1/M in and $5/M out, so a micro per input token and five per
  // output token: 1000 + 10_000 = 11_000 micros, i.e. 1.1 cents.
  assert.equal(row.cost_micros, 11_000);
});

test('a provider that reports no usage is still charged', async () => {
  const world = await fakeWorld({ providerBody: 'data: {"choices":[]}\n' });
  const response = await proxy(proxyRequest('/openai/v1/chat/completions'),
      { env: ENV, fetch: world.fetch });
  await response.text();
  await new Promise((resolve) => setTimeout(resolve, 10));

  const row = JSON.parse(
    world.calls.find((c) => c.url.includes('/usage_events')).init.body,
  );
  assert.equal(row.cost_micros, UNREPORTED_CALL_MICROS);
});

test('a streamed OpenAI call is asked to report its usage', async () => {
  // Without this the meter reads zero for every OpenAI-shaped provider and
  // every call falls back to the flat charge.
  const world = await fakeWorld();
  await proxy(proxyRequest('/openai/v1/chat/completions',
      '{"model":"gpt-4o","stream":true}'), { env: ENV, fetch: world.fetch });

  const upstream = world.calls.find((c) => c.url.includes('api.openai.com'));
  assert.deepEqual(JSON.parse(upstream.init.body).stream_options,
      { include_usage: true });
});

test('a provider SHIFT holds no key for says so, rather than failing oddly',
    async () => {
  const world = await fakeWorld({ hasKey: false });
  const response = await proxy(proxyRequest('/mistral/v1/chat/completions'),
      { env: ENV, fetch: world.fetch });
  assert.equal(response.status, 503);
});

test('a path outside the allowlist never reaches the provider', async () => {
  const world = await fakeWorld();
  const response = await proxy(proxyRequest('/openai/v1/organization/invites'),
      { env: ENV, fetch: world.fetch });

  assert.equal(response.status, 403);
  assert.equal(world.calls.length, 0, 'the entitlement check ran anyway');
});
