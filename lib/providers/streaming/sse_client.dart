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

/// The HTTP client every provider call should use.
///
/// Re-exported from here so the `if (dart.library.js_interop)` pair has exactly
/// one import site. A second one is a second chance to write
/// `dart.library.html`, which is **false** under dart2wasm and would silently
/// select the buffering XHR client in a browser — no error, no exception, just
/// streaming quietly ceasing to stream.
http.Client createProviderHttpClient() => createStreamingClient();

/// A request that was accepted and then never answered.
///
/// Separate from [SseHttpException] because it needs a different sentence and a
/// different remedy: there is no status to read, but unlike a refused request,
/// trying again is a reasonable thing to do.
class SseTimeoutException implements Exception {
  final Duration waited;

  const SseTimeoutException(this.waited);

  @override
  String toString() => 'No response after ${waited.inSeconds}s';
}

/// POSTs JSON and exposes the streamed answer as parsed events.
class SseClient {
  final http.Client Function() _clientFactory;

  /// How long to wait for the response *headers*.
  ///
  /// Without a bound a hung connection sits forever: the composer stays busy,
  /// nothing arrives, and there is no way to tell that from a model thinking.
  /// Only the headers are bounded — once bytes are flowing, a long gap between
  /// deltas is a model working, not a stall, and cutting that off would abort
  /// good replies.
  ///
  /// Private, deliberately. Several test fakes `implements SseClient`, and a
  /// public field would oblige every one of them to declare a timeout they do
  /// not use — a change to this class's contract for something that is an
  /// implementation detail of the real one.
  final Duration _headersTimeout;

  SseClient({
    http.Client Function()? clientFactory,
    this._headersTimeout = const Duration(seconds: 20),
  }) : _clientFactory = clientFactory ?? createStreamingClient;

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

      final response = await client.send(request).timeout(
            _headersTimeout,
            onTimeout: () => throw SseTimeoutException(_headersTimeout),
          );
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
