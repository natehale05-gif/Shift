import 'dart:convert';

import 'package:http/http.dart' as http;

import 'http_client_stub.dart' if (dart.library.html) 'http_client_web.dart';

/// One server-sent event: an `event:` name and its accumulated `data:`
/// payload.
class SseEvent {
  final String event;
  final String data;

  const SseEvent({required this.event, required this.data});
}

/// Folds a stream of text lines into [SseEvent]s per the SSE framing rules
/// used by both Anthropic and Gemini streaming endpoints: `event:`/`data:`
/// fields accumulate until a blank line dispatches the event. Pure Dart —
/// unit-tested against recorded fixtures.
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
    // Comments (:) and unknown fields are ignored per spec.
  }
  if (dataLines.isNotEmpty || eventName.isNotEmpty) {
    yield SseEvent(event: eventName, data: dataLines.join('\n'));
  }
}

/// Thrown when the server answers with a non-2xx status; carries the body
/// so callers can distinguish bad-key (401) from rate limits (429) and
/// overload (529).
class SseHttpException implements Exception {
  final int statusCode;
  final String body;

  const SseHttpException(this.statusCode, this.body);

  @override
  String toString() => 'HTTP $statusCode: $body';
}

/// POSTs a JSON body and exposes the streamed response as parsed SSE
/// events. The underlying client is fetch-based on web (true incremental
/// streaming) and dart:io elsewhere.
class SseClient {
  final http.Client Function() _clientFactory;

  SseClient({http.Client Function()? clientFactory})
      : _clientFactory = clientFactory ?? createStreamingClient;

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
        final errorBody = await response.stream.bytesToString();
        throw SseHttpException(response.statusCode, errorBody);
      }
      final lines = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      yield* parseSseLines(lines);
    } finally {
      client.close();
    }
  }
}
