import 'dart:convert';

import 'package:http/http.dart' as http;

import 'http_client_stub.dart'
    if (dart.library.js_interop) 'http_client_web.dart';

/// One server-sent event: an `event:` name and its accumulated `data:` payload.
class SseEvent {
  final String event;
  final String data;

  const SseEvent({required this.event, required this.data});
}

/// Folds a stream of text lines into [SseEvent]s, per the framing both
/// Anthropic and Gemini use: `event:` and `data:` fields accumulate until a
/// blank line dispatches the event.
///
/// Takes *lines* rather than bytes so the caller owns decoding — which is what
/// makes this pure and fixture-testable, and it is the piece worth keeping
/// unchanged from v1. A trailing event with no blank line after it is still
/// dispatched: some providers close the connection without one, and dropping
/// the last event loses the `message_stop` that ends the turn.
Stream<SseEvent> parseSseLines(Stream<String> lines) async* {
  var eventName = '';
  final dataLines = <String>[];

  await for (final line in lines) {
    if (line.isEmpty) {
      if (dataLines.isNotEmpty || eventName.isNotEmpty) {
        yield SseEvent(event: eventName, data: dataLines.join('\n'));
      }
      eventName = '';
      dataLines.clear();
    } else if (line.startsWith('event:')) {
      eventName = line.substring(6).trim();
    } else if (line.startsWith('data:')) {
      dataLines.add(line.substring(5).trimLeft());
    }
    // Comments (`:`) and unknown fields are ignored, per the spec.
  }

  if (dataLines.isNotEmpty || eventName.isNotEmpty) {
    yield SseEvent(event: eventName, data: dataLines.join('\n'));
  }
}

/// A non-2xx answer, carrying the body.
///
/// The body is kept because the status alone cannot tell a rejected key (401)
/// from a rate limit (429) from an overloaded provider (529), and those three
/// need three different sentences — one is the user's to fix, one resolves by
/// waiting, and one is nobody's fault.
class SseHttpException implements Exception {
  final int statusCode;
  final String body;

  const SseHttpException(this.statusCode, this.body);

  @override
  String toString() => 'HTTP $statusCode: $body';
}

/// POSTs JSON and exposes the streamed answer as parsed events.
class SseClient {
  final http.Client Function() _clientFactory;

  SseClient({http.Client Function()? clientFactory})
      : _clientFactory = clientFactory ?? createStreamingClient;

  /// Which transport this build resolved to. See [streamingClientKind].
  static const String clientKind = streamingClientKind;

  Stream<SseEvent> postJson({
    required Uri uri,
    required Map<String, String> headers,
    required String body,
  }) async* {
    final client = _clientFactory();
    try {
      final request = http.Request('POST', uri)
        ..headers.addAll(headers)
        ..body = body;

      final response = await client.send(request);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw SseHttpException(
          response.statusCode,
          await response.stream.bytesToString(),
        );
      }

      yield* parseSseLines(
        response.stream.transform(utf8.decoder).transform(const LineSplitter()),
      );
    } finally {
      client.close();
    }
  }
}
