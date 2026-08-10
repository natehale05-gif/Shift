import 'dart:convert';

import '../../turn/job_output.dart';
import '../../turn/turn_event.dart';
import '../access.dart';
import '../failure_text.dart';
import '../streaming/reachability.dart';
import '../streaming/sse_client.dart';

/// Talking to the Messages API.
///
/// The wire details here are carried from v1 and reviewed line by line rather
/// than reinvented — each one cost a real debugging session:
///
/// * `anthropic-version` is required, and a *managed* call must not send it.
///   The proxy forwards an allowlist of headers and adds the version itself;
///   sending it from a browser also trips CORS preflight for a header the
///   proxy never asked for.
/// * `temperature` is never sent. Current models reject it outright.
/// * Adaptive thinking needs `display`. Without it the visible text can come
///   back empty — the model thinks, and says nothing.
/// * A trailing SSE event with no blank line after it still counts, which is
///   `parseSseLines`' job and is why `message_stop` is not lost.
class AnthropicText {
  static const apiVersion = '2023-06-01';
  static final _endpoint = Uri.parse('https://api.anthropic.com/v1/messages');

  /// Models that accept `thinking`. Sending it to one that does not is a 400,
  /// so this is a capability list rather than a preference.
  static const thinkingModels = {'claude-opus-4-8', 'claude-sonnet-5'};

  final SseClient _sse;

  /// Asked **only after a transport failure**, never on the happy path.
  ///
  /// Injected so a test can force each answer: the three sentences it chooses
  /// between are unreproducible in this sandbox, because CORS does not exist
  /// off-web and every test and local run here is off-web.
  final Future<Reach> Function() _reach;

  AnthropicText({SseClient? sse, Future<Reach> Function()? reach})
      : _sse = sse ?? SseClient(),
        _reach = reach ?? probeReach;

  /// Where the request goes, and what it carries.
  ///
  /// A managed call keeps the provider's own path and body — the proxy is
  /// transparent — so this method is the only place that has to know which
  /// arm it got.
  ///
  /// Public because the connection test in Settings sends the *same* request
  /// this client does. A test that used a different URL or different headers
  /// would answer a different question from the one being asked.
  static ({Uri uri, Map<String, String> headers}) target(
    ProviderAccess access,
  ) =>
      switch (access) {
        DirectKey(:final key) => (
            uri: _endpoint,
            headers: {
              'content-type': 'application/json',
              'x-api-key': key,
              'anthropic-version': apiVersion,
              // Required for a call made from a browser. Without it Anthropic
              // refuses the origin and the browser blocks the request before
              // it leaves the device — so there is no HTTP status to report
              // and the failure surfaces as a bare transport error.
              //
              // Dropped when porting this client from v1, where it was
              // present and commented. The consequence was invisible off-web,
              // which is where every test and every local run happens, and
              // only appeared on the phone.
              //
              // The name is a warning and it is accurate: it declares that
              // this device is knowingly holding a key. That is true here and
              // deliberately *not* true of a managed call below, which is why
              // it is only on this arm.
              'anthropic-dangerous-direct-browser-access': 'true',
            },
          ),
        ManagedAccess(:final base, :final headers) => (
            uri: base.replace(path: '${base.path}/v1/messages'),
            headers: {'content-type': 'application/json', ...headers},
          ),
      };

  static Map<String, dynamic> buildBody({
    required String model,
    required String instruction,
    String? system,
    int maxTokens = 16000,
    bool thinking = true,
  }) =>
      {
        'model': model,
        'max_tokens': maxTokens,
        if (system != null && system.isNotEmpty) 'system': system,
        'messages': [
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': instruction}
            ],
          }
        ],
        if (thinking && thinkingModels.contains(model))
          'thinking': {'type': 'adaptive', 'display': 'summarized'},
        'stream': true,
      };

  Stream<TurnEvent> stream({
    required String stepId,
    required ProviderAccess access,
    required String model,
    required String instruction,
    String? system,
  }) async* {
    final resolved = target(access);

    // A non-2xx arrives as an exception from the transport, and letting it
    // escape loses the status — the runner's catch-all then says "that step
    // could not be completed", which is true of a rejected key, a rate limit
    // and an outage alike. Three different problems with three different
    // fixes, and only one of them is the user's.
    yield* mapEvents(
      _statusAware(
        _sse.postJson(
          uri: resolved.uri,
          headers: resolved.headers,
          body: jsonEncode(buildBody(
            model: model,
            instruction: instruction,
            system: system,
          )),
        ),
        stepId,
        _reach,
      ),
      stepId: stepId,
    );
  }

  /// Turns a transport-level failure into an `error` frame that says which
  /// failure it was.
  ///
  /// Re-emitted as a frame rather than thrown, so there is exactly one place
  /// that turns a provider problem into a sentence rather than two that can
  /// disagree.
  static Stream<SseEvent> _statusAware(
    Stream<SseEvent> events,
    String stepId,
    Future<Reach> Function() reach,
  ) async* {
    String? sentence;
    String? detail;

    try {
      // `await for`, not `yield*`. A `yield*` forwards a stream's error
      // straight to the consumer without ever throwing inside this function,
      // so the catch below never ran and the status was lost anyway — which
      // is a fix that looks right, compiles, and does nothing.
      await for (final event in events) {
        yield event;
      }
      return;
    } on SseHttpException catch (e) {
      sentence = sentenceForStatus(e.statusCode);
      detail = 'HTTP ${e.statusCode} from api.anthropic.com';
    } on SseTimeoutException catch (e) {
      sentence = sentenceForTimeout;
      detail = '$e · api.anthropic.com';
    } catch (e) {
      // No status at all: the request never completed. From in here a browser
      // refusing it looks exactly like being offline — which is why the
      // sentence is chosen by asking whether *anything* is reachable, rather
      // than by guessing.
      //
      // The exception is kept, not discarded. `catch (_)` threw away the one
      // fact that distinguishes a blocked fetch from a stalled socket, at the
      // only point in the program where that fact exists.
      detail = '$e · api.anthropic.com';
    }

    // Outside the try: awaiting inside a catch and then yielding is legal but
    // reads as if the probe were part of the failing operation, and it is not.
    sentence ??= sentenceForUnreachable(await reach());

    yield SseEvent(
      event: 'error',
      data: jsonEncode({
        'error': {'message': sentence, 'shift_detail': detail}
      }),
    );
  }

  /// Folds the SSE stream into [TurnEvent]s. Static and taking a stream, so
  /// the whole mapping is testable against recorded events with no HTTP at
  /// all — which is what makes the chunk-boundary cases cheap to pin.
  static Stream<TurnEvent> mapEvents(
    Stream<SseEvent> events, {
    required String stepId,
  }) async* {
    final text = StringBuffer();
    final citations = <Citation>[];
    String? stopReason;

    await for (final event in events) {
      if (event.data.isEmpty) continue;

      Map<String, dynamic> payload;
      try {
        payload = jsonDecode(event.data) as Map<String, dynamic>;
      } catch (_) {
        // A malformed frame is skipped rather than fatal: one unparseable
        // event should not discard a reply that is otherwise arriving fine.
        continue;
      }

      switch (event.event) {
        case 'content_block_start':
          final block = payload['content_block'] as Map<String, dynamic>?;
          if (block?['type'] == 'server_tool_use') {
            yield ToolUseStarted(
              stepId,
              block?['name'] as String? ?? 'tool',
            );
          }
          if (block?['type'] == 'web_search_tool_result') {
            yield ToolUseFinished(stepId, 'web_search');
          }

        case 'content_block_delta':
          final delta = payload['delta'] as Map<String, dynamic>?;
          switch (delta?['type']) {
            case 'text_delta':
              final chunk = delta!['text'] as String? ?? '';
              text.write(chunk);
              yield TextDelta(stepId, chunk);
            case 'thinking_delta':
              yield ThinkingDelta(stepId, delta!['thinking'] as String? ?? '');
            case 'citations_delta':
              final citation = delta!['citation'] as Map<String, dynamic>?;
              final url = citation?['url'] as String?;
              if (url != null && !citations.any((c) => c.url.toString() == url)) {
                // The offsets are what make an inline marker possible rather
                // than a chip at the bottom of the message, so they are
                // carried even though nothing renders them yet.
                citations.add(Citation(
                  title: citation?['title'] as String? ?? url,
                  url: Uri.parse(url),
                  start: citation?['start_char_index'] as int?,
                  end: citation?['end_char_index'] as int?,
                ));
              }
          }

        case 'message_delta':
          stopReason =
              (payload['delta'] as Map<String, dynamic>?)?['stop_reason']
                      as String? ??
                  stopReason;

        case 'error':
          final error = payload['error'] as Map<String, dynamic>?;
          yield StepFailed(
            stepId,
            reason: _readable(error?['message']),
            // Only ever set by [_statusAware], which writes it from the
            // exception it caught. A provider's own error body never reaches
            // here — the sentence is what a person reads, and this is what
            // they can paste into a bug report.
            detail: error?['shift_detail'] as String?,
          );
          return;
      }
    }

    if (citations.isNotEmpty) yield CitationsFound(stepId, citations);

    // `max_tokens` means the reply is cut off mid-sentence. v1 shipped a bug
    // here for a whole release: the terminal branch only ran on a clean stop,
    // so a truncated page was held in a buffer and dropped on the floor. What
    // arrived is still worth having, so it completes — and says it is partial
    // rather than presenting half a document as whole.
    final truncated = stopReason == 'max_tokens';

    yield StepCompleted(stepId, TextOutput(text.toString()));

    if (truncated) {
      yield StepFailed(
        stepId,
        reason: 'The reply hit its length limit, so it stops early.',
        blocksDependents: false,
      );
    }
  }

  /// The sentence shown to a person.
  ///
  /// Sentences we wrote pass through; anything the provider itself said does
  /// not, because a raw API message tells the reader nothing they can act on
  /// and occasionally tells them something they should not see.
  static String _readable(Object? message) {
    final text = message is String ? message : '';
    if (writtenSentences.contains(text)) return text;
    if (text.contains('credit') || text.contains('billing')) {
      return sentenceForStatus(402);
    }
    return sentenceForStatus(500);
  }
}
