import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shift/providers/access.dart';
import 'package:shift/providers/clients/anthropic_text.dart';
import 'package:shift/providers/clients/gemini_image.dart';
import 'package:shift/providers/streaming/sse_client.dart';
import 'package:shift/turn/capability.dart';
import 'package:shift/turn/executors/image_executor.dart';
import 'package:shift/turn/executors/text_executor.dart';
import 'package:shift/turn/job_graph.dart';
import 'package:shift/turn/job_output.dart';
import 'package:shift/turn/job_runner.dart';
import 'package:shift/turn/turn_event.dart';

/// One PNG byte, base64'd — enough to prove the decode path without carrying
/// a real image around.
final _pixel = base64Encode([137, 80, 78, 71]);

String imageReply({String? text}) => jsonEncode({
      'candidates': [
        {
          'content': {
            'parts': [
              if (text != null) {'text': text},
              {
                'inlineData': {'mimeType': 'image/png', 'data': _pixel}
              },
            ],
          }
        }
      ],
    });

String textOnlyReply(String text) => jsonEncode({
      'candidates': [
        {
          'content': {
            'parts': [
              {'text': text}
            ]
          }
        }
      ],
    });

class FakeHttp extends http.BaseClient {
  final List<http.BaseRequest> calls = [];
  final int status;
  final String body;

  FakeHttp({this.status = 200, required this.body});

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    calls.add(request);
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      status,
    );
  }
}

JobStep imageStep(String id) => JobStep(
      id: id,
      needs: Capability.image,
      produces: OutputKind.image,
      instruction: 'a sourdough loaf on slate',
      label: 'Drawing',
    );

ImageExecutor executorWith(FakeHttp http, {ProviderAccess? credential}) =>
    ImageExecutor(
      usable: (_) => true,
      access: (_) async => credential ?? const DirectKey('AIza-test'),
      gemini: GeminiImage(clientFactory: () => http),
    );

void main() {
  group('generating a picture', () {
    test('an inline image becomes a typed output', () async {
      final transport = FakeHttp(body: imageReply());
      final events = await executorWith(transport)
          .run(imageStep('image'), const {})
          .toList();

      final done = events.whereType<StepCompleted>().single;
      final image = done.output as ImageOutput;
      expect(image.bytes, isNotEmpty);
      expect(image.prompt, 'a sourdough loaf on slate',
          reason: 'the prompt is carried so a later step can caption it');
    });

    test('the request asks for an image, not a description of one', () async {
      // Without responseModalities the model writes about the picture instead
      // of drawing it — a reply that looks like success and contains none.
      final body = GeminiImage.buildBody('a loaf');
      expect(
        (body['generationConfig'] as Map)['responseModalities'],
        ['TEXT', 'IMAGE'],
      );
    });

    test('text with no image is a failure with a reason, not empty success',
        () async {
      // A refusal is a real answer. Reporting it as a provider fault sends the
      // user to retry something that will never work.
      final transport = FakeHttp(body: textOnlyReply("I can't draw that."));
      final events = await executorWith(transport)
          .run(imageStep('image'), const {})
          .toList();

      expect(events.whereType<StepCompleted>(), isEmpty);
      expect(events.whereType<StepFailed>().single.reason,
          contains('did not produce an image'));
    });

    test('a rejected key says so, distinctly from a rate limit', () async {
      final rejected = await executorWith(FakeHttp(status: 401, body: '{}'))
          .run(imageStep('i'), const {})
          .toList();
      final limited = await executorWith(FakeHttp(status: 429, body: '{}'))
          .run(imageStep('i'), const {})
          .toList();

      expect(rejected.whereType<StepFailed>().single.reason,
          contains('rejected'));
      expect(limited.whereType<StepFailed>().single.reason,
          contains('rate limiting'));
    });

    test('an unreadable body fails rather than throwing', () async {
      final events = await executorWith(FakeHttp(body: 'not json'))
          .run(imageStep('i'), const {})
          .toList();
      expect(events.whereType<StepFailed>(), hasLength(1));
    });
  });

  group('credentials', () {
    test('a direct call puts the key in the URL, which is Gemini\'s scheme',
        () async {
      final transport = FakeHttp(body: imageReply());
      await executorWith(transport).run(imageStep('i'), const {}).toList();
      expect(transport.calls.single.url.query, contains('AIza-test'));
    });

    test('a managed call puts no key anywhere', () async {
      // The custody argument again, and here it is also a logging one: a key
      // in a URL ends up in proxy and CDN logs.
      final transport = FakeHttp(body: imageReply());
      await executorWith(
        transport,
        credential: ManagedAccess(
          base: Uri.parse('https://proxy.test/pp/gemini'),
          headers: const {'Authorization': 'Bearer session'},
        ),
      ).run(imageStep('i'), const {}).toList();

      final request = transport.calls.single;
      expect(request.url.query, isEmpty);
      expect(request.url.toString(), isNot(contains('AIza')));
      expect(request.headers['Authorization'], 'Bearer session');
    });

    test('nothing available spends nothing', () async {
      final transport = FakeHttp(body: imageReply());
      final events = await ImageExecutor(
        usable: (_) => false,
        access: (_) async => null,
        gemini: GeminiImage(clientFactory: () => transport),
      ).run(imageStep('i'), const {}).toList();

      expect(events.whereType<StepFailed>(), hasLength(1));
      expect(transport.calls, isEmpty);
    });
  });

  group('the two-provider turn, with both halves real', () {
    test('one provider draws, another writes, and the writer is told what '
        'the picture shows', () async {
      // The headline requirement, now with no stub on either side: real client
      // code, real request bodies, real response parsing, fake sockets only.
      final drawing = FakeHttp(body: imageReply());
      final writing = _FakeSse();

      final graph = JobGraph.build([
        imageStep('image'),
        JobStep(
          id: 'page',
          needs: Capability.text,
          produces: OutputKind.text,
          after: const ['image'],
          instruction: 'build a page for the bakery',
          label: 'Building',
        ),
      ]).graph!;

      final events = await JobRunner({
        Capability.image: ImageExecutor(
          usable: (_) => true,
          access: (_) async => const DirectKey('AIza-test'),
          gemini: GeminiImage(clientFactory: () => drawing),
        ),
        Capability.text: TextExecutor(
          usable: (_) => true,
          access: (_) async => const DirectKey('sk-ant-test'),
          anthropic: AnthropicText(sse: writing),
        ),
      }).run(graph).toList();

      expect(events.whereType<StepStarted>().map((e) => e.provider),
          ['Gemini', 'Claude'],
          reason: 'two different companies did the two halves');

      expect(writing.bodies.single, contains('a sourdough loaf on slate'),
          reason: 'the page step consumed the image rather than merely '
              'running after it');

      expect((events.last as TurnFinished).incomplete, isFalse);
    });

    test('a failed picture still lets the page be written', () async {
      // v1 collapsed the whole turn when one provider faltered, discarding
      // work already paid for.
      final drawing = FakeHttp(status: 429, body: '{}');
      final writing = _FakeSse();

      final graph = JobGraph.build([
        imageStep('image'),
        JobStep(
          id: 'page',
          needs: Capability.text,
          produces: OutputKind.text,
          after: const ['image'],
          instruction: 'build a page',
          label: 'Building',
        ),
      ]).graph!;

      final events = await JobRunner({
        Capability.image: ImageExecutor(
          usable: (_) => true,
          access: (_) async => const DirectKey('AIza-test'),
          gemini: GeminiImage(clientFactory: () => drawing),
        ),
        Capability.text: TextExecutor(
          usable: (_) => true,
          access: (_) async => const DirectKey('sk-ant-test'),
          anthropic: AnthropicText(sse: writing),
        ),
      }).run(graph).toList();

      expect((events.last as TurnFinished).incomplete, isTrue,
          reason: 'the turn must admit it is partial');
    });
  });
}

class _FakeSse implements SseClient {
  final List<String> bodies = [];

  @override
  Stream<SseEvent> postJson({
    required Uri uri,
    required Map<String, String> headers,
    required String body,
  }) {
    bodies.add(body);
    return Stream.fromIterable(const [
      SseEvent(
          event: 'content_block_start',
          data: '{"content_block":{"type":"text","text":""}}'),
      SseEvent(
          event: 'content_block_delta',
          data: '{"delta":{"type":"text_delta","text":"the page"}}'),
      SseEvent(event: 'message_stop', data: '{}'),
    ]);
  }
}
