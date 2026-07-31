// Reads token counts out of a provider's response as it streams past.
//
// The meter cannot ask what a call will cost before making it — nobody knows
// until the reply ends. So the ceiling is checked *before* dispatch and the
// cost is recorded *after*, which means one call can overshoot the ceiling by
// its own size. That is inherent, bounded by a single request, and better than
// the alternative of refusing to stream so the cost can be known first.
//
// Three providers, three shapes, one scanner. Rather than a parser per
// provider it looks at every JSON object that goes by and picks up whichever
// known shape appears — which also means a provider that changes its event
// names keeps metering as long as the usage object is recognisable.

export class UsageMeter {
  constructor() {
    this.inputTokens = 0;
    this.outputTokens = 0;
    this.model = null;
    this._buffer = '';
  }

  /** True once any usage at all has been seen. */
  get sawUsage() {
    return this.inputTokens > 0 || this.outputTokens > 0;
  }

  /**
   * Feeds a chunk of the response body. Safe to call with arbitrary
   * boundaries — a JSON object split across two chunks is held until the rest
   * arrives, because a half-parsed number is a wrong number.
   */
  write(text) {
    this._buffer += text;

    // Server-sent events are newline delimited, so a complete line is a
    // complete payload. Anything after the last newline is a partial and stays
    // in the buffer.
    const lines = this._buffer.split('\n');
    this._buffer = lines.pop() ?? '';

    for (const line of lines) {
      const payload = line.startsWith('data:') ? line.slice(5).trim() : line.trim();
      if (payload.length === 0 || payload === '[DONE]') continue;
      this._absorb(payload);
    }
  }

  /** Call once the body has ended, to take in whatever was left over. */
  flush() {
    const rest = this._buffer.trim();
    this._buffer = '';
    if (rest.length === 0) return;
    const payload = rest.startsWith('data:') ? rest.slice(5).trim() : rest;
    this._absorb(payload);
  }

  _absorb(payload) {
    let json;
    try {
      json = JSON.parse(payload);
    } catch {
      return; // Not JSON — a comment, a keepalive, a fragment of prose.
    }
    if (json === null || typeof json !== 'object') return;
    this._walk(json, 0);
  }

  /**
   * Looks for a usage object anywhere in the payload.
   *
   * Depth-limited: a hostile or merely enormous response should not be able to
   * turn metering into a stack overflow, which would take the request down
   * with it — and a failed request is one that was never charged for.
   */
  _walk(node, depth) {
    if (depth > 6 || node === null || typeof node !== 'object') return;

    if (typeof node.model === 'string' && this.model === null) {
      this.model = node.model;
    }

    // Anthropic: {usage: {input_tokens, output_tokens}}, split across
    // message_start and message_delta.
    // OpenAI:    {usage: {prompt_tokens, completion_tokens}}
    const usage = node.usage;
    if (usage && typeof usage === 'object') {
      this._add(usage.input_tokens ?? usage.prompt_tokens, 'inputTokens');
      this._add(usage.output_tokens ?? usage.completion_tokens, 'outputTokens');
    }

    // Gemini
    const meta = node.usageMetadata;
    if (meta && typeof meta === 'object') {
      this._replace(meta.promptTokenCount, 'inputTokens');
      this._replace(meta.candidatesTokenCount, 'outputTokens');
    }

    for (const value of Object.values(node)) {
      if (Array.isArray(value)) {
        for (const item of value) this._walk(item, depth + 1);
      } else if (value && typeof value === 'object') {
        this._walk(value, depth + 1);
      }
    }
  }

  /**
   * Anthropic reports input once and output in pieces, so those accumulate —
   * but it also repeats the input count on the final delta, so take the
   * maximum rather than summing. Summing double-charged every call.
   */
  _add(value, field) {
    if (typeof value !== 'number' || !Number.isFinite(value) || value < 0) return;
    this[field] = Math.max(this[field], value);
  }

  /** Gemini reports a running total, so the last value wins outright. */
  _replace(value, field) {
    if (typeof value !== 'number' || !Number.isFinite(value) || value < 0) return;
    this[field] = value;
  }
}

/**
 * Wraps a response body so it streams to the client unchanged while the meter
 * reads it.
 *
 * The client's bytes are never held back or altered: metering is our
 * bookkeeping, and a member should not wait on it or notice it. [onDone] runs
 * when the body ends, including when the client disconnects early — a call
 * that was half-received still cost what it cost.
 */
export function meteredBody(body, meter, onDone) {
  if (!body) {
    onDone(meter);
    return null;
  }

  const decoder = new TextDecoder();
  let finished = false;
  const finish = () => {
    if (finished) return;
    finished = true;
    meter.flush();
    onDone(meter);
  };

  return body.pipeThrough(
    new TransformStream({
      transform(chunk, controller) {
        controller.enqueue(chunk);
        try {
          meter.write(decoder.decode(chunk, { stream: true }));
        } catch {
          // Metering must never break the stream the member is reading. A
          // miscounted call is a bookkeeping problem; a truncated reply is
          // their work disappearing mid-sentence.
        }
      },
      flush() {
        finish();
      },
      cancel() {
        finish();
      },
    }),
  );
}
