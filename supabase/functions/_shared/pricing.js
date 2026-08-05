// What a proxied call costs the account, in millionths of a dollar.
//
// The numbers below are list prices per million tokens. They will drift, and
// that is fine — this is a meter for a spend ceiling, not an invoice. What
// matters is the direction it drifts in, which is why the fallback exists.
//
// **An unknown model is charged the most expensive rate here, not zero.**
// Getting this backwards is the failure that costs real money: a member on a
// model the table has not heard of would spend SHIFT's key for free and the
// ceiling would never stop them. Overcharging an unrecognised model is
// recoverable — somebody complains and the table gets a row. Undercharging it
// is an unbounded bill nobody notices until it arrives.

/** Dollars per million tokens, as micros per million (so $5.00 -> 5_000_000). */
const RATES = {
  // Anthropic
  'claude-opus-4-8': { input: 5_000_000, output: 25_000_000 },
  'claude-opus-4-7': { input: 5_000_000, output: 25_000_000 },
  'claude-opus-4-6': { input: 5_000_000, output: 25_000_000 },
  'claude-sonnet-5': { input: 3_000_000, output: 15_000_000 },
  'claude-sonnet-4-6': { input: 3_000_000, output: 15_000_000 },
  'claude-haiku-4-5': { input: 1_000_000, output: 5_000_000 },
  'claude-fable-5': { input: 10_000_000, output: 50_000_000 },
};

/**
 * The rate used when the model is not in the table.
 *
 * Set to the most expensive row rather than an average, on purpose — see the
 * note at the top of this file.
 */
const FALLBACK = { input: 10_000_000, output: 50_000_000 };

/**
 * What one call cost, rounded **up** to the next micro.
 *
 * Rounding up rather than to nearest because a call that reports one token
 * should not be free: thousands of them would be, and the meter would read
 * zero while the provider's invoice did not.
 */
export function costMicros({ model, inputTokens = 0, outputTokens = 0 }) {
  const rate = rateFor(model);
  const total =
    inputTokens * rate.input + outputTokens * rate.output;
  return Math.ceil(total / 1_000_000);
}

export function rateFor(model) {
  if (typeof model !== 'string' || model.length === 0) return FALLBACK;
  if (RATES[model]) return RATES[model];

  // Providers append dates and suffixes (`gpt-4o-2024-08-06`). Prefer the
  // longest matching prefix so a specific row wins over a general one.
  let best = null;
  for (const known of Object.keys(RATES)) {
    if (model.startsWith(known) && (!best || known.length > best.length)) {
      best = known;
    }
  }
  return best ? RATES[best] : FALLBACK;
}

/**
 * What to charge when a call completed but reported no usage at all.
 *
 * Not zero. A provider that streams a reply and reports nothing — or a
 * response shape the meter does not recognise — must still cost something, or
 * "make the usage unparseable" becomes a way to spend for free. Roughly a
 * medium reply on the fallback rate.
 */
export const UNREPORTED_CALL_MICROS = 20_000;

/**
 * What one generated image costs, in millionths of a dollar.
 *
 * $0.20, which is above the top of OpenAI's current per-image range rather
 * than in the middle of it — the same principle as pricing an unknown model at
 * the most expensive rate. An image reports no tokens at all, so there is
 * nothing to measure after the fact; the choice is between a number set high
 * enough that the ceiling still means something and one that lets a member
 * spend ten times their plan on pictures.
 *
 * Over-charging is visible and correctable — it shows up as spend against a
 * ceiling somebody can raise. Under-charging is invisible until the provider
 * bill arrives.
 */
export const IMAGE_CALL_MICROS = 200_000;

/**
 * What one generated video costs, in millionths of a dollar.
 *
 * $2.00. Video is the most expensive thing a membership can buy and the
 * hardest to bound: an avatar render or a Sora clip is priced by length, and
 * the length is in the request rather than the reply. Set above the range on
 * purpose — a $25 plan should buy roughly a dozen videos, and a member who
 * wants more can be granted more, which is a conversation. The alternative is
 * discovering the real number on the provider's invoice.
 */
export const VIDEO_CALL_MICROS = 2_000_000;

/**
 * What one speech or music generation costs.
 *
 * $0.10. ElevenLabs bills per character and per second, neither of which comes
 * back in the response, so this is a per-call figure above a typical clip
 * rather than a measurement.
 */
export const SPEECH_CALL_MICROS = 100_000;

/**
 * What a status poll costs: nothing.
 *
 * Video and speech are asynchronous, so one deliverable is a submit and then a
 * dozen polls. Charging them would make waiting cost more than generating —
 * two dozen polls at the unreported-call rate is nearly fifty cents of nothing
 * happening — and the polls are our client's doing, not a member's request.
 *
 * Free is safe here because of what a poll can be: the allowlist's GET entries
 * are status, listing and content. None of them generates anything, so there
 * is no way to make work free by relabelling it.
 */
export const POLL_CALL_MICROS = 0;

/**
 * The per-call price for a kind of work, or null when it is metered on tokens.
 *
 * Null rather than a default, so a caller has to decide what to do about it —
 * text falls through to the token meter, and a kind added later without a
 * price shows up as a missing case rather than as a quiet zero.
 */
export function fixedPriceFor(kind) {
  return FIXED_PRICES[kind] ?? null;
}

const FIXED_PRICES = {
  image: IMAGE_CALL_MICROS,
  video: VIDEO_CALL_MICROS,
  speech: SPEECH_CALL_MICROS,
  poll: POLL_CALL_MICROS,
};
