// The bundler is on the deploy path, so it gets tested like one.
//
// `tool/bundle_function.py` inlines every `_shared` import into a single file,
// and that file — not the directory — is what the management API deploys and
// what a dashboard paste receives. Everything the other suites assert is about
// the *sources*; nothing until now looked at what is actually shipped.
//
// The failure this exists to catch is specific: inlining flattens several
// modules into one scope, so two `_shared` files that happen to define the same
// name produce a file that is a syntax error or, worse, silently uses the wrong
// one. The import regex is also line-shaped, and `admin-membership`'s import
// spans six lines. Either fault is a 500 on the first real request and is
// invisible to every test that imports the sources directly.

import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');

/** Every function that has a bundle to build — i.e. all of them. */
const FUNCTIONS = [
  'provider-key',
  'provider-proxy',
  'admin-membership',
  'stripe-webhook',
];

function build(name, ...flags) {
  const printed = execFileSync(
    'python3',
    [path.join(ROOT, 'tool/bundle_function.py'), name, ...flags],
    { cwd: ROOT, encoding: 'utf8' },
  ).trim();
  const file = path.join(ROOT, printed);
  assert.ok(existsSync(file), `${name}: the bundler printed a path it did not write`);
  return file;
}

for (const name of FUNCTIONS) {
  test(`${name} bundles into one importable module`, async () => {
    // Importing is most of the assertion: a duplicate top-level `const`, a
    // stripped `export` that left a dangling reference, or an import the regex
    // failed to remove all throw here rather than in production.
    const module = await import(pathToFileURL(build(name)).href);
    assert.equal(typeof module.handle, 'function',
      `${name}: the bundle must still export the handler it is deployed for`);
  });

  test(`${name}'s bundle answers a request`, async () => {
    const module = await import(pathToFileURL(build(name)).href);

    // A preflight, because it is the one request every handler answers
    // identically and without touching a database, a key or an upstream. It
    // reaching a Response at all proves the inlined `_shared` code is wired up
    // — `corsHeaders` lives in `handler.js`, two modules away from the entry.
    const response = await module.handle(
      new Request('https://x.test/functions/v1/x', { method: 'OPTIONS' }),
      { env: {}, fetch: async () => new Response('', { status: 200 }) },
    );

    assert.equal(response.status, 204);
    assert.equal(response.headers.get('Access-Control-Allow-Origin'), '*');
  });

  test(`${name} survives having its comments stripped`, async () => {
    // `--lean` is what actually gets deployed through the management API, so
    // it is the artifact that has to work — not the readable one. The risk it
    // carries is specific: a comment stripper that cannot tell `//` in a
    // comment from `//` in `'https://api.anthropic.com'` produces a file that
    // still looks fine and is silently wrong.
    const module = await import(pathToFileURL(build(name, '--lean')).href);
    assert.equal(typeof module.handle, 'function');

    const response = await module.handle(
      new Request('https://x.test/functions/v1/x', { method: 'OPTIONS' }),
      { env: {}, fetch: async () => new Response('', { status: 200 }) },
    );
    assert.equal(response.status, 204);
  });
}

test('stripping comments leaves every URL intact', () => {
  // The failure this pins: `upstream.js` is a table of provider hosts, and a
  // host that lost its `//` would send a member's request somewhere that is
  // not the provider — with SHIFT's key attached.
  const full = readFileSync(build('provider-proxy'), 'utf8');
  const lean = readFileSync(build('provider-proxy', '--lean'), 'utf8');

  const urls = (text) => (text.match(/https:\/\/[\w.-]+/g) ?? []).sort();
  assert.deepEqual(new Set(urls(lean)), new Set(urls(full)));
  assert.ok(urls(lean).includes('https://api.anthropic.com'));
});

test('the --deno bundle carries an entrypoint, and the plain one does not', () => {
  // The difference between the two outputs is the entire reason the flag
  // exists. A `--deno` bundle without the serve line deploys and answers
  // nothing; a plain bundle with it cannot be imported by the tests above,
  // since `Deno` is not defined here.
  const plain = execFileSync(
    'python3',
    [path.join(ROOT, 'tool/bundle_function.py'), 'provider-proxy'],
    { cwd: ROOT, encoding: 'utf8' },
  ).trim();
  const deno = execFileSync(
    'python3',
    [path.join(ROOT, 'tool/bundle_function.py'), 'provider-proxy', '--deno'],
    { cwd: ROOT, encoding: 'utf8' },
  ).trim();

  assert.ok(deno.endsWith('.deno.ts'), 'the deno bundle is a separate artifact');
  assert.notEqual(plain, deno);

  const text = readFileSync(path.join(ROOT, deno), 'utf8');
  assert.match(text, /Deno\.serve\(\(req\) => handle\(req, \{ env: Deno\.env\.toObject\(\), fetch \}\)\);/);

  const plainText = readFileSync(path.join(ROOT, plain), 'utf8');
  assert.doesNotMatch(plainText, /Deno\.serve/);
});
