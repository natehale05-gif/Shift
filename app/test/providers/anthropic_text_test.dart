import 'package:flutter_test/flutter_test.dart';
import 'package:shift/providers/access.dart';
import 'package:shift/providers/clients/anthropic_text.dart';
import 'package:shift/providers/streaming/sse_client.dart';
import 'package:shift/turn/job_output.dart';
import 'package:shift/turn/turn_event.dart';

/// Recorded event shapes, replayed as a stream. Nothing here touches HTTP —
/// the mapping is where the bugs live, and it is pure.
Stream<SseEvent> replay(List<(String, String)> events) =>
    Stream.fromIterable(events.map((e) => SseEvent(event: e.$1, data: e.$2)));

const _blockStart =
    ('content_block_start', '{"content_block":{"type":"text","text":""}}');

(String, String) delta(String text) => (
      'content_block_delta',
      '{"delta":{"type":"text_delta","text":"$text"}}',
    );

Future<List<TurnEvent>> run(List<(String, String)> events) =>
    AnthropicText.mapEvents(replay(events), stepId: 's').toList();

void main() {
  group('an ordinary reply', () {
    test('deltas stream and the whole text completes', () async {
      final events = await run([
        ('message_start', '{"message":{"usage":{"input_tokens":10}}}'),
        _blockStart,
        delta('Hello'),
        delta(' there'),
        ('message_delta', '{"delta":{"stop_reason":"end_turn"}}'),
        ('message_stop', '{}'),
      ]);

      expect(events.whereType<TextDelta>().map((e) => e.text),
          ['Hello', ' there']);

      final done = events.whereType<StepCompleted>().single;
      expect((done.output as TextOutput).text, 'Hello there');
      expect(events.whereType<StepFailed>(), isEmpty);
    });

    test('thinking is separated from the answer', () async {
      // If reasoning were folded into the text, it would render as prose the
      // user did not ask for — and would end up in the artifact.
      final events = await run([
        ('content_block_delta',
            '{"delta":{"type":"thinking_delta","thinking":"weighing it"}}'),
        _blockStart,
        delta('Yes.'),
        ('message_stop', '{}'),
      ]);

      expect(events.whereType<ThinkingDelta>().single.text, 'weighing it');
      expect((events.whereType<StepCompleted>().single.output as TextOutput).text,
          'Yes.');
    });
  });

  group('the truncated reply, which v1 lost entirely', () {
    test('a max_tokens stop still completes with what arrived', () async {
      // The v1 regression this exists to prevent: the terminal branch ran only
      // on a clean finish, so a reply cut off by the output ceiling was held
      // in a buffer and silently discarded. The user asked for a website, saw
      // the intro sentence, and then nothing at all. Half a page is worth
      // having; no page is not.
      final events = await run([
        _blockStart,
        delta('<!DOCTYPE html><html>'),
        ('message_delta', '{"delta":{"stop_reason":"max_tokens"}}'),
        ('message_stop', '{}'),
      ]);

      final done = events.whereType<StepCompleted>().single;
      expect((done.output as TextOutput).text, '<!DOCTYPE html><html>');
    });

    test('and says it is partial without blocking what comes next', () async {
      final events = await run([
        _blockStart,
        delta('half a page'),
        ('message_delta', '{"delta":{"stop_reason":"max_tokens"}}'),
      ]);

      final warning = events.whereType<StepFailed>().single;
      expect(warning.reason, contains('length limit'));
      expect(warning.blocksDependents, isFalse,
          reason: 'a downstream step should get the partial text, not nothing');
    });
  });

  group('failures', () {
    test('an error event ends the step and emits no output', () async {
      final events = await run([
        _blockStart,
        delta('start'),
        ('error', '{"error":{"message":"overloaded_error"}}'),
        delta('this should never be reached'),
      ]);

      expect(events.whereType<StepCompleted>(), isEmpty,
          reason: 'a failed step must not also report success');
      expect(events.whereType<StepFailed>(), hasLength(1));
      expect(events.whereType<TextDelta>(), hasLength(1));
    });

    test('the raw provider message is not shown to the user', () async {
      final events = await run([
        ('error', '{"error":{"message":"overloaded_error"}}'),
      ]);
      expect(events.whereType<StepFailed>().single.reason,
          isNot(contains('overloaded_error')));
    });

    test('a credit failure says so, because only the user can fix it',
        () async {
      final events = await run([
        ('error', '{"error":{"message":"Your credit balance is too low"}}'),
      ]);
      expect(events.whereType<StepFailed>().single.reason, contains('credit'));
    });

    test('a malformed frame is skipped, not fatal', () async {
      // One unparseable event should not discard a reply that is otherwise
      // arriving perfectly well.
      final events = await run([
        _blockStart,
        delta('before'),
        ('content_block_delta', 'not json at all'),
        delta(' after'),
        ('message_stop', '{}'),
      ]);
      expect((events.whereType<StepCompleted>().single.output as TextOutput).text,
          'before after');
    });
  });

  group('citations carry their spans', () {
    test('offsets survive, because a chip at the bottom is not the goal',
        () async {
      final events = await run([
        _blockStart,
        delta('The sky is blue.'),
        (
          'content_block_delta',
          '{"delta":{"type":"citations_delta","citation":'
              '{"url":"https://example.test/a","title":"A",'
              '"start_char_index":4,"end_char_index":16}}}'
        ),
        ('message_stop', '{}'),
      ]);

      final citation = events.whereType<CitationsFound>().single.citations.single;
      expect(citation.url.toString(), 'https://example.test/a');
      expect(citation.hasSpan, isTrue);
      expect(citation.start, 4);
    });

    test('the same source twice is one citation', () async {
      const one = (
        'content_block_delta',
        '{"delta":{"type":"citations_delta","citation":'
            '{"url":"https://example.test/a","title":"A"}}}'
      );
      final events = await run([_blockStart, one, one, ('message_stop', '{}')]);
      expect(events.whereType<CitationsFound>().single.citations, hasLength(1));
    });

    test('a source with no offsets still arrives, without a fake span',
        () async {
      final events = await run([
        (
          'content_block_delta',
          '{"delta":{"type":"citations_delta","citation":'
              '{"url":"https://example.test/b","title":"B"}}}'
        ),
        ('message_stop', '{}'),
      ]);
      final citation = events.whereType<CitationsFound>().single.citations.single;
      expect(citation.hasSpan, isFalse,
          reason: 'guessing a position is worse than rendering it as a source');
    });
  });

  group('the request body', () {
    test('never sends temperature — current models reject it', () {
      final body = AnthropicText.buildBody(
        model: 'claude-opus-4-8',
        instruction: 'hi',
      );
      expect(body.containsKey('temperature'), isFalse);
    });

    test('adaptive thinking carries display, or the text comes back empty', () {
      final body = AnthropicText.buildBody(
        model: 'claude-opus-4-8',
        instruction: 'hi',
      );
      expect(body['thinking'], {'type': 'adaptive', 'display': 'summarized'});
    });

    test('a model that cannot think is not asked to', () {
      final body = AnthropicText.buildBody(
        model: 'claude-haiku-4-5',
        instruction: 'hi',
      );
      expect(body.containsKey('thinking'), isFalse,
          reason: 'sending thinking to a model without it is a 400');
    });
  });

  group('managed calls', () {
    test('carry no key and no version header', () async {
      // Both matter and for different reasons: the key is the custody
      // argument, and `anthropic-version` is not on the proxy's forwarded
      // allowlist — sending it from a browser fails CORS preflight for a
      // header the proxy never asked for.
      Uri? seen;
      Map<String, String>? sentHeaders;

      final client = AnthropicText(
        sse: _RecordingSse((uri, headers) {
          seen = uri;
          sentHeaders = headers;
        }),
      );

      await client
          .stream(
            stepId: 's',
            access: ManagedAccess(
              base: Uri.parse('https://proxy.test/functions/v1/pp/anthropic'),
              headers: const {'Authorization': 'Bearer session'},
            ),
            model: 'claude-opus-4-8',
            instruction: 'hi',
          )
          .toList();

      expect(sentHeaders!.containsKey('x-api-key'), isFalse);
      expect(sentHeaders!.containsKey('anthropic-version'), isFalse);
      expect(sentHeaders!['Authorization'], 'Bearer session');
      expect(seen!.path, endsWith('/v1/messages'));
    });

    test('a direct call carries both', () async {
      Map<String, String>? sentHeaders;
      final client = AnthropicText(
        sse: _RecordingSse((_, headers) => sentHeaders = headers),
      );

      await client
          .stream(
            stepId: 's',
            access: const DirectKey('sk-ant-test'),
            model: 'claude-opus-4-8',
            instruction: 'hi',
          )
          .toList();

      expect(sentHeaders!['x-api-key'], 'sk-ant-test');
      expect(sentHeaders!['anthropic-version'], AnthropicText.apiVersion);
    });
  });
}

class _RecordingSse implements SseClient {
  final void Function(Uri, Map<String, String>) onCall;

  _RecordingSse(this.onCall);

  @override
  Stream<SseEvent> postJson({
    required Uri uri,
    required Map<String, String> headers,
    required String body,
  }) {
    onCall(uri, headers);
    return const Stream.empty();
  }
}
