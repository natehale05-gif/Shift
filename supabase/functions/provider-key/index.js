// Store a provider key. The only way a secret enters the vault.
//
// The client cannot write `provider_keys` directly — the column holds
// ciphertext and the key that produces it is not something a browser is
// allowed to hold. So this endpoint is the encrypting front door, and the row
// policy plus column privileges in `0003_provider_keys.sql` are what make it
// the *only* door.
//
// What comes back is metadata: an id and the last four characters. The secret
// is never returned, by this call or any other, which is the property that
// makes a vault worth having over storing keys on the device.

import {
  bytesToHex,
  lastFour,
  masterKeyBytes,
  masterKeyId,
  seal,
} from '../_shared/crypto.js';
import { json, problem, serviceRequest, withAdapter } from '../_shared/handler.js';

/** Providers the app knows how to spend. An unknown one is a typo, not a key. */
const KNOWN_PROVIDERS = new Set([
  'anthropic',
  'openai',
  'gemini',
  'groq',
  'mistral',
  'openrouter',
  'flux',
  'heygen',
  'elevenlabs',
]);

export const handle = withAdapter(async (req, ctx) => {
  if (req.method !== 'POST') return problem(405, 'Use POST.');

  let body;
  try {
    body = await req.json();
  } catch {
    return problem(400, 'Expected a JSON body.');
  }

  const provider = String(body?.provider ?? '').trim().toLowerCase();
  // Whitespace anywhere, not just at the ends: a key pasted from an email
  // arrives with line breaks in the middle, and `trim()` leaves those in —
  // which sends a 401 and blames the key. Same fix the client made in F3.
  const secret = String(body?.secret ?? '').replace(/\s+/g, '');

  if (!KNOWN_PROVIDERS.has(provider)) {
    return problem(400, `Unknown provider "${provider}".`);
  }
  if (secret.length < 8) {
    return problem(400, 'That does not look like a key.');
  }

  const sealed = await seal(secret, masterKeyBytes(ctx.env));

  // Upsert on (owner_id, provider, key_owner) so replacing a key is the same
  // call as adding one. Someone rotating a key should not have to delete the
  // old one first and be left with none if the second step fails.
  const response = await serviceRequest(ctx, '/provider_keys?on_conflict=owner_id,provider,key_owner', {
    method: 'POST',
    headers: {
      Prefer: 'resolution=merge-duplicates,return=representation',
    },
    body: JSON.stringify({
      owner_id: ctx.userId,
      provider,
      key_owner: 'user',
      ciphertext: bytesToHex(sealed),
      kms_key_id: masterKeyId(ctx.env),
      last_four: lastFour(secret),
      updated_at: new Date().toISOString(),
    }),
  });

  const rows = await response.json();
  const row = Array.isArray(rows) ? rows[0] : rows;

  return json({
    id: row?.id ?? '',
    provider,
    last_four: row?.last_four ?? lastFour(secret),
  });
});

// Supabase edge functions serve the module's default export.
export default { fetch: (req) => handle(req, { env: readEnv() }) };

/** Deno and Node expose the environment differently; this is the only place
 *  that has to know, which is what keeps the handler itself portable. */
function readEnv() {
  // eslint-disable-next-line no-undef
  if (typeof Deno !== 'undefined') return Deno.env.toObject();
  return globalThis.process?.env ?? {};
}
