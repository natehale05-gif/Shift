import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shift/providers/access.dart';
import 'package:shift/providers/clients/anthropic_text.dart';
import 'package:shift/providers/clients/gemini_text.dart';
import 'package:shift/providers/clients/openai_text.dart';
import 'package:shift/providers/failure_text.dart';
import 'package:shift/providers/streaming/reachability.dart';
import 'package:shift/providers/streaming/sse_client.dart';
import 'package:shift/turn/capability.dart';
import 'package:shift/turn/executors/text_executor.dart';
import 'package:shift/turn/job_graph.dart';
import 'package:shift/turn/job_output.dart';
import 'package:shift/turn/job_runner.dart';
import 'package:shift/turn/turn_event.dart';

/// A transport, not a client: the real `AnthropicText` mapping runs on top of
/// it. So these exercise request construction and event folding for real, and
/// only the socket is fake.
class FakeTransport implements SseClient {
  final List<({Uri uri, String body})> calls = [];
  final List<(String, String)> events;

  FakeTransport(this.events);

  @override
  Stream<SseEvent> postJson({
    required Uri uri,
    required Map<String, String> headers,
    required String body,
  }) {
    calls.add((uri: uri, body: body));
    return Stream.fromIterable(
      events.map((e) => SseEvent(event: e.$1, data: e.$2)),
    );
  }
}

List<(String, String)> saying(String text) => [
      ('content_block_start', '{"content_block":{"type":"text","text":""}}'),
      ('content_block_delta', '{"delta":{"type":"text_delta","text":"$text"}}'),
      ('message_stop', '{}'),
    ];

JobStep step(String id, {List<String> after = const []}) => JobStep(
      id: id,
      needs: Capability.text,
      produces: OutputKind.text,
      after: after,
      instruction: 'write the page',
      label: id,
    );

void main() {
  group('choosing and paying', () {
    test('no provider at all fails with something the user can act on',
        () async {
      final transport = FakeTransport(const []);
      final executor = TextExecutor(
        usable: (_) => false,
        access: (_) async => null,
        anthropic: AnthropicText(sse: transport),
      );

      final events = await executor.run(step('main'), const {}).toList();

      expect(events.whereType<StepFailed>().single.reason,
          allOf(contains('Settings'), contains('plan')));
      expect(transport.calls, isEmpty,
          reason: 'nothing may be spent when nothing was available — '
              '"it failed" and "it failed without a request" are different');
    });

    test('a usable provider with no credential still spends nothing', () async {
      // The gap worth separating: selection said yes, the credential said no.
      // Sending the request anyway would produce a 401 the user reads as a
      // bad key when the truth is there is no key.
      final transport = FakeTransport(const []);
      final executor = TextExecutor(
        usable: (_) => true,
        access: (_) async => null,
        anthropic: AnthropicText(sse: transport),
      );

      await executor.run(step('main'), const {}).toList();
      expect(transport.calls, isEmpty);
    });

    test('the managed path is preferred and carries no key', () async {
      final transport = FakeTransport(saying('done'));
      final executor = TextExecutor(
        usable: (_) => true,
        access: (_) async => ManagedAccess(
          base: Uri.parse('https://proxy.test/pp/anthropic'),
          headers: const {'Authorization': 'Bearer session'},
        ),
        anthropic: AnthropicText(sse: transport),
      );

      await executor.run(step('main'), const {}).toList();
      expect(transport.calls.single.uri.host, 'proxy.test');
    });
  });

  group('the two-provider turn, one layer below the runner', () {
    test('the page step is told what the picture shows', () async {
      // The headline requirement, asserted where it can actually go wrong.
      // The runner test already proves the image output *reaches* the page
      // step; this proves the page step does something with it. Without this,
      // the two steps run in order, the feature looks correct in a log, and
      // the page never mentions the picture.
      final transport = FakeTransport(saying('a page'));
      final executor = TextExecutor(
        usable: (_) => true,
        access: (_) async => const DirectKey('sk-ant-test'),
        anthropic: AnthropicText(sse: transport),
      );

      await executor.run(
        step('page', after: ['image']),
        {
          'image': ImageOutput(
            bytes: Uint8List.fromList([1]),
            mimeType: 'image/png',
            prompt: 'a sourdough loaf on slate',
          ),
        },
      ).toList();

      expect(transport.calls.single.body,
          contains('a sourdough loaf on slate'));
    });

    test('runs end to end through the graph with two different providers',
        () async {
      // Same shape as the runner's own test, but the text half is the real
      // client on a fake socket rather than a stub — so request construction
      // and SSE folding are inside the assertion.
      final transport = FakeTransport(saying('the page'));
      final drawer = _FakeImages();

      final graph = JobGraph.build([
        JobStep(
          id: 'image',
          needs: Capability.image,
          produces: OutputKind.image,
          instruction: 'a loaf',
          label: 'Drawing',
        ),
        step('page', after: ['image']),
      ]).graph!;

      final events = await JobRunner({
        Capability.image: drawer,
        Capability.text: TextExecutor(
          usable: (_) => true,
          access: (_) async => const DirectKey('sk-ant-test'),
          anthropic: AnthropicText(sse: transport),
        ),
      }).run(graph).toList();

      final started = events.whereType<StepStarted>().toList();
      expect(started.map((e) => e.provider), ['openai', 'Claude'],
          reason: 'each step reports its own provider');

      expect(transport.calls.single.body, contains('a loaf'),
          reason: 'the writing step consumed the image');
      expect((events.last as TurnFinished).incomplete, isFalse);
    });
  });

  group('what the UI is told before the work starts', () {
    test('the provider is named up front', () {
      final executor = TextExecutor(
        usable: (_) => true,
        access: (_) async => const DirectKey('k'),
      );
      final who = executor.identify(step('main'));
      expect(who.provider, 'Claude');
      expect(who.model, isNotEmpty);
    });

    test('and says so honestly when there is nobody', () {
      final executor = TextExecutor(
        usable: (_) => false,
        access: (_) async => null,
      );
      expect(executor.identify(step('main')).provider, 'unavailable');
    });
  });

  group('a request the browser never let out', () {
    // The report: "some keys are not working in my desktop browsers, I tried
    // chrome and brave". Both browsers were behaving correctly; the app told
    // them to try another one, for a provider whose CORS behaviour is not
    // established. The chat turn is where that sentence was read, so it is the
    // path this pins — Settings' Test connection is the second surface, not
    // the first.

    Future<String> reasonFor({
      required bool onWeb,
      required String providerId,
    }) async {
      final executor = TextExecutor(
        usable: (id) => id == providerId,
        access: (_) async => const DirectKey('k'),
        anthropic: AnthropicText(
          sse: RefusingTransport(),
          reach: () async => Reach.up,
        ),
        gemini: GeminiText(
          sse: RefusingTransport(),
          reach: () async => Reach.up,
        ),
        openai: OpenAiText(
          sse: RefusingTransport(),
          reach: () async => Reach.up,
        ),
        onWeb: onWeb,
      );
      final events = await executor.run(step('main'), const {}).toList();
      return events.whereType<StepFailed>().single.reason;
    }

    test('an unverified provider on the web names the real possibility',
        () async {
      final reason = await reasonFor(onWeb: true, providerId: 'groq');
      expect(reason, contains('Groq'));
      expect(reason, contains('desktop app'));
      expect(reason, isNot(contains('try another browser')));
    });

    test('Claude keeps the generic sentence, because Claude does work',
        () async {
      // Measured: api.anthropic.com answers `access-control-allow-origin: *`
      // and allows the headers this client sends. So a blocked request there
      // really is something local, and blaming the provider would be false.
      final reason = await reasonFor(onWeb: true, providerId: 'anthropic');
      expect(reason, sentenceForUnreachable(Reach.up));
    });

    test('and off the web nobody is blamed at all', () async {
      // There is no CORS outside a browser. The desktop and mobile builds can
      // call every provider here.
      final reason = await reasonFor(onWeb: false, providerId: 'groq');
      expect(reason, sentenceForUnreachable(Reach.up));
      expect(reason, isNot(contains('Groq')));
    });

    test('a failure that already has a status does not spend a probe',
        () async {
      // Threading the sentence through meant hoisting `await reach()` out of a
      // `??=`, which silently made every rejected key cost an extra request —
      // for a question the 401 had already answered. Asserted directly,
      // because a wasted round trip is invisible from the outside.
      var probes = 0;
      final executor = TextExecutor(
        usable: (_) => true,
        access: (_) async => const DirectKey('k'),
        anthropic: AnthropicText(
          sse: _RejectingTransport(401),
          reach: () async {
            probes++;
            return Reach.up;
          },
        ),
        onWeb: true,
      );

      final events = await executor.run(step('main'), const {}).toList();

      expect(events.whereType<StepFailed>().single.reason,
          contains('key was rejected'));
      expect(probes, 0, reason: 'the status said everything already');
    });

    test('the sentence survives the error frame it travels in', () async {
      // `readErrorFrame` filters anything it does not recognise down to a
      // generic 500 — so a new sentence that is not in the allowlist would be
      // silently replaced, and the whole fix would vanish one layer below
      // where it was written.
      final reason = await reasonFor(onWeb: true, providerId: 'groq');
      expect(writtenSentences, contains(reason));
    });
  });
}

class _FakeImages implements StepExecutor {
  @override
  ({String provider, String model}) identify(JobStep step) =>
      (provider: 'openai', model: 'gpt-image-1');

  @override
  Stream<TurnEvent> run(JobStep step, Map<String, JobOutput> inputs) async* {
    yield StepCompleted(
      step.id,
      ImageOutput(
        bytes: Uint8List.fromList([1]),
        mimeType: 'image/png',
        prompt: 'a loaf',
      ),
    );
  }
}

/// A transport that fails the way a browser refusing a cross-origin request
/// does: no status, no response, just a thrown error.
class RefusingTransport implements SseClient {
  @override
  Stream<SseEvent> postJson({
    required Uri uri,
    required Map<String, String> headers,
    required String body,
  }) =>
      Stream<SseEvent>.error(
        Exception('ClientException: Failed to fetch, uri=$uri'),
      );
}

/// A transport that fails the way a provider rejecting a key does: with a
/// status, which is all the information the sentence needs.
class _RejectingTransport implements SseClient {
  final int status;

  _RejectingTransport(this.status);

  @override
  Stream<SseEvent> postJson({
    required Uri uri,
    required Map<String, String> headers,
    required String body,
  }) =>
      Stream<SseEvent>.error(SseHttpException(status, 'nope'));
}
