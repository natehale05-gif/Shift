// Envelope encryption for the key vault.
//
// Written against WebCrypto and nothing else, so the same file runs on Deno
// (Supabase edge functions), Node 18+, Bun and Cloudflare Workers. That is the
// portability requirement applied to the one piece of code it would be most
// painful to rewrite under pressure.
//
// **What this is, honestly.** The master key comes from an environment
// variable, not from a hosted KMS. The shape is a KMS's shape — a master key
// that never leaves the server, a per-record data key, and a `kms_key_id`
// column recording which master encrypted what so a rotation can find its work
// — but the master itself is held by the platform's secret store rather than by
// AWS KMS or Cloud KMS. Moving to a real one replaces `masterKey()` and nothing
// else; the record format does not change.
//
// AES-256-GCM, random 12-byte IV per record, and the auth tag GCM appends is
// what makes a tampered ciphertext fail to decrypt rather than decrypt to
// garbage.

const IV_BYTES = 12;

/**
 * The master key, as raw bytes.
 *
 * Throws rather than defaulting. A vault that silently encrypts under a
 * predictable key is worse than one that refuses to start: nothing looks wrong
 * until the day somebody reads the table.
 *
 * @param {Record<string, string | undefined>} env
 * @returns {Uint8Array}
 */
export function masterKeyBytes(env) {
  const raw = env.SHIFT_KMS_KEY;
  if (!raw) {
    throw new Error('SHIFT_KMS_KEY is not set — refusing to store secrets.');
  }

  // Strip whitespace before decoding. This value is pasted by a human, often
  // from a phone, and a trailing newline is invisible in every UI that shows
  // it — but `atob` rejects it, so the vault would fail on every call with an
  // error that names the key and tells you nothing about why. Base64 has no
  // whitespace in it, so removing it cannot change a valid value. Same lesson
  // as F3, where a provider key pasted with a line break in it produced a 401
  // that blamed the key.
  const cleaned = raw.replace(/\s+/g, '');

  let bytes;
  try {
    bytes = base64ToBytes(cleaned);
  } catch {
    throw new Error(
      'SHIFT_KMS_KEY is not valid base64. Generate a fresh one rather than ' +
        'editing this by hand.',
    );
  }

  if (bytes.length !== 32) {
    throw new Error(
      `SHIFT_KMS_KEY must decode to 32 bytes for AES-256, got ${bytes.length}. ` +
        'It should be the 44-character string a generator produced, ending "=".',
    );
  }
  return bytes;
}

/** Which master encrypted a record, so a rotation knows what still needs it. */
export function masterKeyId(env) {
  return env.SHIFT_KMS_KEY_ID || 'default';
}

/**
 * Encrypts `plaintext` and returns the stored record: IV followed by
 * ciphertext, one buffer, because splitting them across columns only creates a
 * way for them to get separated.
 *
 * @param {string} plaintext
 * @param {Uint8Array} keyBytes
 * @returns {Promise<Uint8Array>}
 */
export async function seal(plaintext, keyBytes) {
  const key = await importKey(keyBytes);
  const iv = crypto.getRandomValues(new Uint8Array(IV_BYTES));
  const ciphertext = new Uint8Array(
    await crypto.subtle.encrypt(
      { name: 'AES-GCM', iv },
      key,
      new TextEncoder().encode(plaintext),
    ),
  );
  const record = new Uint8Array(iv.length + ciphertext.length);
  record.set(iv, 0);
  record.set(ciphertext, iv.length);
  return record;
}

/**
 * Reverses {@link seal}. Throws on a tampered or truncated record rather than
 * returning something that looks like a key — a wrong key sent to a provider
 * is a 401 the user cannot explain.
 *
 * @param {Uint8Array} record
 * @param {Uint8Array} keyBytes
 * @returns {Promise<string>}
 */
export async function open(record, keyBytes) {
  if (record.length <= IV_BYTES) {
    throw new Error('Stored key is truncated.');
  }
  const key = await importKey(keyBytes);
  const iv = record.slice(0, IV_BYTES);
  const ciphertext = record.slice(IV_BYTES);
  const plaintext = await crypto.subtle.decrypt(
    { name: 'AES-GCM', iv },
    key,
    ciphertext,
  );
  return new TextDecoder().decode(plaintext);
}

/**
 * The last four characters of a secret, which is all a client is ever told
 * about a stored key.
 *
 * Short secrets are masked entirely rather than half-revealed: four of six
 * characters is most of the key.
 *
 * @param {string} secret
 */
export function lastFour(secret) {
  const trimmed = secret.trim();
  return trimmed.length >= 8 ? trimmed.slice(-4) : '••••';
}

async function importKey(keyBytes) {
  return crypto.subtle.importKey('raw', keyBytes, { name: 'AES-GCM' }, false, [
    'encrypt',
    'decrypt',
  ]);
}

/** Postgres `bytea` in hex form, which is what PostgREST accepts and returns. */
export function bytesToHex(bytes) {
  let out = '\\x';
  for (const byte of bytes) out += byte.toString(16).padStart(2, '0');
  return out;
}

export function hexToBytes(hex) {
  const body = hex.startsWith('\\x') ? hex.slice(2) : hex;
  const out = new Uint8Array(body.length / 2);
  for (let i = 0; i < out.length; i++) {
    out[i] = parseInt(body.substr(i * 2, 2), 16);
  }
  return out;
}

export function base64ToBytes(value) {
  const binary = atob(value);
  const out = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) out[i] = binary.charCodeAt(i);
  return out;
}
