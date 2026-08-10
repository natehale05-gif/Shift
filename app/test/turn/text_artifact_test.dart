import 'package:flutter_test/flutter_test.dart';
import 'package:shift/providers/access.dart';
import 'package:shift/providers/clients/anthropic_text.dart';
import 'package:shift/providers/streaming/sse_client.dart';
import 'package:shift/turn/capability.dart';
import 'package:shift/turn/executors/text_executor.dart';
import 'package:shift/turn/job_graph.dart';
import 'package:shift/turn/job_output.dart';
import 'package:shift/turn/turn_event.dart';

/// The page arrives once, and never disappears.
///
/// Both halves are v1 defects that shipped: F5 sent the page twice — as markup
/// in the transcript *and* as the artifact — and the fix for it (v0.1.5) then
/// dropped truncated pages entirely, which was strictly worse.
void main() {
  const page = '''
<!DOCTYPE html>
<html>
<head><title>Coffee</title></head>
<body><h1>Coffee shop</h1><p>Open daily.</p></body>
</html>''';

  Future<List<TurnEvent>> runWith(List<SseEvent> frames) async {
    final executor = TextExecutor(
      usable: (_) => true,
      access: (_) async => const DirectKey('sk-ant-x'),
      anthropic: AnthropicText(sse: _Canned(frames)),
      conversationId: () => 'c1',
    );
    return executor
        .run(
          const JobStep(
            id: 's',
            label: 'Writing',
            needs: Capability.text,
            produces: OutputKind.text,
            instruction: 'build me a coffee shop website',
          ),
          const {},
        )
        .toList();
  }

  List<SseEvent> stream(List<String> deltas, {String stop = 'end_turn'}) => [
        const SseEvent(
            event: 'content_block_start',
            data: '{"content_block":{"type":"text","text":""}}'),
        for (final d in deltas)
          SseEvent(
            event: 'content_block_delta',
            data: '{"delta":{"type":"text_delta","text":${_json(d)}}}',
          ),
        SseEvent(
            event: 'message_delta', data: '{"delta":{"stop_reason":"$stop"}}'),
        const SseEvent(event: 'message_stop', data: '{}'),
      ];

  test('the page becomes an artifact and never reaches the transcript',
      () async {
    final events = await runWith(stream([
      "Here's a complete coffee shop website:\n",
      '```html\n',
      page,
      '\n```',
    ]));

    final artifact = events.whereType<ArtifactProduced>().single.artifact;
    expect(artifact.title, 'Coffee');

    final shown = events.whereType<TextDelta>().map((e) => e.text).join();
    expect(shown, contains("Here's a complete"));
    expect(shown, isNot(contains('<h1>')),
        reason: 'the page arriving twice is what this wave exists to stop');
  });

  test('a block that is not a deliverable comes back into the reply',
      () async {
    // v1's F5 shipped the deletion version of this and lost whole answers.
    final events = await runWith(stream([
      'Centre it with flexbox:\n',
      '```css\n.a { display: flex }\n```',
      '\nThat is all you need, and here is a long explanation of why. ' * 20,
    ]));

    expect(events.whereType<ArtifactProduced>(), isEmpty);
    final shown = events.whereType<TextDelta>().map((e) => e.text).join();
    expect(shown, contains('display: flex'),
        reason: 'withholding is a presentation choice, never a deletion');
  });

  test('a reply truncated mid-page still shows what arrived', () async {
    // v1's F6, exactly: the terminal branch ran only on a clean finish, so a
    // page cut off at the token ceiling was held in a buffer and dropped. The
    // symptom was prose promising a website followed by nothing at all.
    final events = await runWith(stream([
      "Here's the site:\n",
      '```html\n<!DOCTYPE html>\n<html>\n<body><h1>Coff',
    ], stop: 'max_tokens'));

    expect(events.whereType<ArtifactProduced>(), isEmpty,
        reason: 'half a document previews as a broken page');
    final shown = events.whereType<TextDelta>().map((e) => e.text).join();
    expect(shown, contains('<h1>Coff'));
    expect(shown.trimRight(), endsWith('```'),
        reason: 'an open fence renders every later message as code');
  });

  test('a failed step does not swallow the block either', () async {
    final events = await runWith([
      const SseEvent(
        event: 'content_block_delta',
        data: '{"delta":{"type":"text_delta","text":"```html\\n<html><b"}}',
      ),
      const SseEvent(
        event: 'error',
        data: '{"error":{"message":"Rate limited. Try again in a moment."}}',
      ),
    ]);

    final shown = events.whereType<TextDelta>().map((e) => e.text).join();
    expect(shown, contains('<html><b'));
    expect(events.whereType<StepFailed>(), isNotEmpty);
  });

  test('the step output still carries the whole reply', () async {
    // What the person is shown and what the next step receives are different
    // questions. A page step feeding another step must not lose the page.
    final events = await runWith(stream(['```html\n', page, '\n```']));
    expect(events.whereType<StepCompleted>(), isNotEmpty);
  });
}

String _json(String value) => value
    .replaceAll(r'\', r'\\')
    .replaceAll('"', r'\"')
    .replaceAll('\n', r'\n')
    .let((s) => '"$s"');

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}

class _Canned implements SseClient {
  final List<SseEvent> frames;

  _Canned(this.frames);

  @override
  Stream<SseEvent> postJson({
    required Uri uri,
    required Map<String, String> headers,
    required String body,
  }) =>
      Stream.fromIterable(frames);
}
