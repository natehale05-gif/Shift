import 'dart:convert';

import '../../turn/history.dart';
import '../../turn/job_output.dart';
import '../../turn/turn_event.dart';
import '../access.dart';
import '../streaming/reachability.dart';
import '../streaming/sse_client.dart';
import '../streaming/status_aware.dart';

/// Talking to Gemini's `generateContent`, streamed.
///
/// The wire is not Anthropic's and the differences are the whole reason this is
/// a separate client rather than a parameter:
///
/// * **`?alt=sse` or it is not a stream.** Without it the endpoint answers with
///   one JSON array at the end, which arrives looking exactly like a very slow
///   model.
/// * **There are no event names.** Every frame is an unnamed `data:` line, so
///   the fold switches on the payload's shape rather than on `event.event`.
/// * **A direct call puts the key in the query string.** That is Gemini's own
///   scheme for browsers, and it is why a managed call must *not* — the proxy
///   sets `x-goog-api-key` server-side, keeping it out of every access log
///   between here and Google.
/// * **Sources arrive as `groundingMetadata`**, not as citation deltas, and
///   only on the chunks that have them — so they are accumulated and emitted
///   once at the end rather than per frame.
class GeminiText {
  static const _host = 'generativelanguage.googleapis.com';

  final SseClient _sse;
  final Future<Reach> Function() _reach;

  GeminiText({SseClient? sse, Future<Reach> Function()? reach})
      : _sse = sse ?? SseClient(),
        _reach = reach ?? probeReach;

  /// Public for the same reason Anthropic's is: a connection test that used a
  /// different URL would answer a different question.
  static ({Uri uri, Map<String, String> headers}) target(
    ProviderAccess access,
    String model,
  ) =>
      switch (access) {
        DirectKey(:final key) => (
            uri: Uri.https(_host, '/v1beta/models/$model:streamGenerateContent',
                {'alt': 'sse', 'key': key}),
            headers: const {'content-type': 'application/json'},
          ),
        ManagedAccess(:final base, :final headers) => (
            uri: base.replace(
              path: '${base.path}/v1beta/models/$model:streamGenerateContent',
              queryParameters: const {'alt': 'sse'},
            ),
            headers: {'content-type': 'application/json', ...headers},
          ),
      };

  static Map<String, dynamic> buildBody({
    required String instruction,
    String? system,
    List<Exchange> history = const [],
  }) =>
      {
        'contents': [
          // Gemini calls the assistant's turn `model`, not `assistant`. Same
          // shape otherwise, and the same alternation guarantee.
          for (final past in history) ...[
            {
              'role': 'user',
              'parts': [
                {'text': past.asked}
              ],
            },
            {
              'role': 'model',
              'parts': [
                {'text': past.answered}
              ],
            },
          ],
          {
            'role': 'user',
            'parts': [
              {'text': instruction}
            ],
          }
        ],
        // Gemini's system prompt is its own field, not a message with a role.
        // Sent as a `user` turn instead, it becomes part of the conversation
        // and the model answers it.
        if (system != null && system.isNotEmpty)
          'systemInstruction': {
            'parts': [
              {'text': system}
            ],
          },
      };

  Stream<TurnEvent> stream({
    required String stepId,
    required ProviderAccess access,
    required String model,
    required String instruction,
    String? system,
    String? blocked,
    List<Exchange> history = const [],
  }) async* {
    final resolved = target(access, model);

    yield* mapEvents(
      statusAware(
        _sse.postJson(
          uri: resolved.uri,
          headers: resolved.headers,
          body: jsonEncode(buildBody(
            instruction: instruction,
            system: system,
            history: history,
          )),
        ),
        host: _host,
        reach: _reach,
        blocked: blocked,
      ),
      stepId: stepId,
    );
  }

  /// Folds Gemini's frames into [TurnEvent]s. Static and taking a stream, so
  /// the shape can be pinned against recorded payloads with no HTTP at all.
  static Stream<TurnEvent> mapEvents(
    Stream<SseEvent> events, {
    required String stepId,
  }) async* {
    final text = StringBuffer();
    final sources = <String, Citation>{};
    String? finishReason;

    await for (final event in events) {
      if (event.data.isEmpty) continue;

      Map<String, dynamic> payload;
      try {
        payload = jsonDecode(event.data) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }

      // Only [statusAware] produces a named frame; everything Gemini sends is
      // unnamed.
      if (event.event == 'error') {
        final failure = readErrorFrame(payload);
        yield StepFailed(stepId, reason: failure.reason, detail: failure.detail);
        return;
      }

      final candidates = payload['candidates'] as List<dynamic>? ?? const [];
      if (candidates.isEmpty) continue;
      final candidate = candidates.first as Map<String, dynamic>;

      final parts = (candidate['content'] as Map<String, dynamic>?)?['parts']
              as List<dynamic>? ??
          const [];
      for (final part in parts) {
        final chunk = (part as Map<String, dynamic>)['text'] as String?;
        if (chunk == null || chunk.isEmpty) continue;
        text.write(chunk);
        yield TextDelta(stepId, chunk);
      }

      final grounding =
          candidate['groundingMetadata'] as Map<String, dynamic>?;
      for (final entry
          in grounding?['groundingChunks'] as List<dynamic>? ?? const []) {
        final web = (entry as Map<String, dynamic>)['web']
            as Map<String, dynamic>?;
        final url = web?['uri'] as String?;
        if (url == null) continue;
        // Keyed by url, because the same source is cited by several chunks and
        // a list would repeat it once per sentence it supported.
        sources[url] ??= Citation(
          title: web?['title'] as String? ?? url,
          url: Uri.parse(url),
        );
      }

      finishReason = candidate['finishReason'] as String? ?? finishReason;
    }

    if (sources.isNotEmpty) {
      yield CitationsFound(stepId, sources.values.toList());
    }

    yield StepCompleted(stepId, TextOutput(text.toString()));

    // Gemini's word for hitting the ceiling. Same treatment as Anthropic's
    // `max_tokens`: what arrived is worth having, and it says it is partial
    // rather than presenting half a document as whole.
    if (finishReason == 'MAX_TOKENS') {
      yield StepFailed(
        stepId,
        reason: 'The reply hit its length limit, so it stops early.',
        blocksDependents: false,
      );
    }
  }
}
