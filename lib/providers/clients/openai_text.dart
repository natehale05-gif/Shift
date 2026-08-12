import 'dart:convert';

import '../../turn/history.dart';
import '../../turn/job_output.dart';
import '../../turn/turn_event.dart';
import '../access.dart';
import '../streaming/reachability.dart';
import '../streaming/sse_client.dart';
import '../streaming/status_aware.dart';

/// Talking to any provider that speaks OpenAI's `chat/completions`.
///
/// One client for OpenAI, Groq, Mistral and OpenRouter, because the wire is
/// genuinely the same and four near-identical files would be four places for a
/// fix to be applied three times. What differs is the base URL, which comes
/// from the registry.
///
/// Wire details that matter:
///
/// * **`[DONE]` is not JSON.** The stream ends with a literal `data: [DONE]`,
///   and decoding it throws — which, caught, looks like a malformed frame and
///   silently truncates the reply.
/// * **A delta can have no content.** The first frame carries only `role`, and
///   tool-call frames carry no text at all.
/// * **`finish_reason` is on the choice, not the payload**, and `'length'` is
///   this family's word for hitting the ceiling.
class OpenAiText {
  final SseClient _sse;
  final Future<Reach> Function() _reach;

  OpenAiText({SseClient? sse, Future<Reach> Function()? reach})
      : _sse = sse ?? SseClient(),
        _reach = reach ?? probeReach;

  /// The full path at the provider, `/v1` included.
  ///
  /// **Both arms derive from this**, and they used to not. The direct arm
  /// inherited `/v1` from the registry's `baseUrl` — every one of the four is
  /// exactly `host + /v1` — while the managed arm rebuilt the path from the
  /// proxy's base and dropped it. `/v1` is the only thing the proxy's allowlist
  /// matches on, so every managed turn on OpenAI, Groq, Mistral and OpenRouter
  /// came back 403 and read as a rejected key.
  ///
  /// `tool/scan_proxy_providers.py` checks this against the server's own
  /// allowlist, because nothing was comparing the two and that gap is exactly
  /// the width of that bug.
  static const providerPath = '/v1/chat/completions';

  /// What follows the registry's `baseUrl`, which already ends in `/v1`.
  static const _suffix = '/chat/completions';

  static Uri endpoint(String baseUrl) {
    final trimmed =
        baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    return Uri.parse('$trimmed$_suffix');
  }

  static ({Uri uri, Map<String, String> headers}) target(
    ProviderAccess access,
    String baseUrl,
  ) =>
      switch (access) {
        DirectKey(:final key) => (
            uri: endpoint(baseUrl),
            headers: {
              'content-type': 'application/json',
              'authorization': 'Bearer $key',
            },
          ),
        // The proxy is transparent: the path is the provider's own, and which
        // provider it forwards to is decided server-side from the slug in
        // [base], never from a header a client could change.
        ManagedAccess(:final base, :final headers) => (
            uri: base.replace(path: '${base.path}$providerPath'),
            headers: {'content-type': 'application/json', ...headers},
          ),
      };

  static Map<String, dynamic> buildBody({
    required String model,
    required String instruction,
    String? system,
    List<Exchange> history = const [],
  }) =>
      {
        'model': model,
        'messages': [
          if (system != null && system.isNotEmpty)
            {'role': 'system', 'content': system},
          for (final past in history) ...[
            {'role': 'user', 'content': past.asked},
            {'role': 'assistant', 'content': past.answered},
          ],
          {'role': 'user', 'content': instruction},
        ],
        'stream': true,
      };

  Stream<TurnEvent> stream({
    required String stepId,
    required ProviderAccess access,
    required String model,
    required String baseUrl,
    required String instruction,
    String? system,
    String? blocked,
    List<Exchange> history = const [],
  }) async* {
    final resolved = target(access, baseUrl);

    yield* mapEvents(
      statusAware(
        _sse.postJson(
          uri: resolved.uri,
          headers: resolved.headers,
          body: jsonEncode(buildBody(
            model: model,
            instruction: instruction,
            system: system,
            history: history,
          )),
        ),
        host: resolved.uri.host,
        reach: _reach,
        blocked: blocked,
        // Which reader a failing status gets. The clients already know:
        // `target` matched on the arm to build the URL.
        managed: access is ManagedAccess,
      ),
      stepId: stepId,
    );
  }

  static Stream<TurnEvent> mapEvents(
    Stream<SseEvent> events, {
    required String stepId,
  }) async* {
    final text = StringBuffer();
    String? finishReason;

    await for (final event in events) {
      if (event.data.isEmpty) continue;

      // Not JSON, and decoding it throws. Skipped as "malformed" it would look
      // identical to a truncated reply.
      if (event.data.trim() == '[DONE]') break;

      Map<String, dynamic> payload;
      try {
        payload = jsonDecode(event.data) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }

      if (event.event == 'error') {
        final failure = readErrorFrame(payload);
        yield StepFailed(stepId, reason: failure.reason, detail: failure.detail);
        return;
      }

      final choices = payload['choices'] as List<dynamic>? ?? const [];
      if (choices.isEmpty) continue;
      final choice = choices.first as Map<String, dynamic>;

      final chunk =
          (choice['delta'] as Map<String, dynamic>?)?['content'] as String?;
      if (chunk != null && chunk.isNotEmpty) {
        text.write(chunk);
        yield TextDelta(stepId, chunk);
      }

      finishReason = choice['finish_reason'] as String? ?? finishReason;
    }

    yield StepCompleted(stepId, TextOutput(text.toString()));

    if (finishReason == 'length') {
      yield StepFailed(
        stepId,
        reason: 'The reply hit its length limit, so it stops early.',
        blocksDependents: false,
      );
    }
  }
}
