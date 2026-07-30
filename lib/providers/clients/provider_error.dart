import 'dart:convert';

import '../streaming/sse_client.dart';

/// Turns whatever a provider failed with into a sentence.
///
/// Reported from a live run: a turn ended with
///
///     Something went wrong: HTTP 400: {"type":"error","error":{"type":
///     "invalid_request_error","message":"messages.1.content: 'image' blocks
///     are not permitted within assistant turns."},"request_id":"req_011…"}
///
/// printed into the chat. Two things wrong with that. It is unreadable — the
/// one useful sentence is buried in JSON — and on a phone it fills the screen.
///
/// The opposite mistake is just as bad here, though, and worth naming because
/// it is the tempting fix: collapsing everything to "something went wrong"
/// would be worse for this app than for most. People bring their own keys, so
/// *which* failure it was is the whole diagnosis — a rejected key, a spent
/// quota and a malformed request need three different actions, and only the
/// provider knows which one happened.
///
/// So: keep the provider's own sentence, drop the envelope, and say what to do
/// about the statuses where the answer is known.
String readableProviderError(Object error, {String provider = 'The provider'}) {
  if (error is! SseHttpException) {
    // Not an HTTP answer at all — offline, DNS, a blocked proxy.
    return 'Could not reach $provider. Check your connection and try again.';
  }

  final detail = _messageIn(error.body);

  return switch (error.statusCode) {
    400 || 422 => detail == null
        ? '$provider rejected the request.'
        : '$provider rejected the request: $detail',
    401 || 403 => 'That API key was rejected. Check it in Settings — most '
        'often the paste was incomplete.',
    402 => 'That account is out of credit.',
    404 => detail == null
        ? 'That model is not available on this key.'
        : 'Not available: $detail',
    413 => 'That request was too large. Try a shorter message or fewer '
        'attachments.',
    429 => 'Rate limited right now. Wait a moment and try again.',
    >= 500 => '$provider is having trouble right now (${error.statusCode}). '
        'Try again shortly.',
    _ => detail == null
        ? '$provider returned an error (${error.statusCode}).'
        : '$provider: $detail',
  };
}

/// The human sentence a provider buried in its error envelope.
///
/// Anthropic nests it under `error.message`, OpenAI under `error.message` too,
/// Gemini under `error.message`, and some proxies just send `message`. Any
/// shape that is not recognised yields null rather than a guess, and the
/// caller says something generic — a wrong guess reads as the app inventing an
/// explanation.
String? _messageIn(String body) {
  if (body.trim().isEmpty) return null;
  try {
    final decoded = jsonDecode(body);
    if (decoded is! Map) return null;

    final error = decoded['error'];
    final candidate = error is Map
        ? (error['message'] ?? error['detail'])
        : (decoded['message'] ?? decoded['detail'] ?? error);

    if (candidate is! String || candidate.trim().isEmpty) return null;

    // Long provider messages are usually a stack of validation paths. The
    // first sentence carries the fault; the rest is where it was found.
    final text = candidate.trim();
    return text.length > 300 ? '${text.substring(0, 297)}…' : text;
  } on FormatException {
    return null;
  }
}
