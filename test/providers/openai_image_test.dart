import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shift/providers/access.dart';
import 'package:shift/providers/clients/openai_image.dart';
import 'package:shift/providers/streaming/reachability.dart';
import 'package:shift/turn/job_output.dart';
import 'package:shift/turn/turn_event.dart';

/// Making a picture with OpenAI.
///
/// The reported symptom, with an OpenAI key saved and no Gemini key: "generate
/// an image of a pink flower" → *"OpenAI images are not wired up yet."* It was
/// the only image provider available and there was nothing behind it.
void main() {
  /// A one-pixel PNG, so the decode is real rather than asserted around.
  const pixel =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

  http.Client answering(
    String body, {
    int status = 200,
    void Function(http.Request)? record,
  }) =>
      MockClient((request) async {
        record?.call(request);
        return http.Response(body, status,
            headers: const {'content-type': 'application/json'});
      });

  Future<List<TurnEvent>> run(
    http.Client client, {
    String? aspectRatio,
    Future<Reach> Function()? reach,
  }) =>
      OpenAiImage(clientFactory: () => client, reach: reach)
          .generate(
            stepId: 'image',
            access: const DirectKey('sk-test'),
            model: 'gpt-image-1',
            baseUrl: 'https://api.openai.com/v1',
            prompt: 'a pink flower',
            aspectRatio: aspectRatio,
            blocked: 'OpenAI may not allow calls from a web page.',
          )
          .toList();

  test('a picture comes back as bytes, not a URL', () async {
    // gpt-image-1 only ever returns base64. A client written against the older
    // models would look for a URL and find nothing.
    final events = await run(answering(jsonEncode({
      'data': [
        {'b64_json': pixel}
      ]
    })));

    final output = events.whereType<StepCompleted>().single.output;
    expect(output, isA<ImageOutput>());
    final image = output as ImageOutput;
    expect(image.bytes, isNotEmpty);
    expect(image.prompt, 'a pink flower');
    // A real PNG header, so "there are bytes" and "the bytes are a picture"
    // are distinguishable.
    expect(image.bytes.take(4), [0x89, 0x50, 0x4E, 0x47]);
  });

  test('it says it is working before the wait, not after', () async {
    // A picture takes tens of seconds and reports nothing while it does.
    final events = await run(answering(jsonEncode({
      'data': [
        {'b64_json': pixel}
      ]
    })));

    expect(events.first, isA<StepProgress>());
  });

  group('the request', () {
    Future<Map<String, dynamic>> bodyFor(String? aspectRatio) async {
      late http.Request seen;
      await run(
        answering(
          jsonEncode({
            'data': [
              {'b64_json': pixel}
            ]
          }),
          record: (r) => seen = r,
        ),
        aspectRatio: aspectRatio,
      );
      return jsonDecode(seen.body) as Map<String, dynamic>;
    }

    test('never sends response_format', () async {
      // gpt-image-1 rejects it outright — a 400 for a field that does nothing.
      expect(await bodyFor(null), isNot(contains('response_format')));
    });

    test('maps a shape to a size the endpoint accepts', () async {
      // An arbitrary ratio is a 400, so the ratio the planner speaks in is
      // mapped rather than passed through.
      expect((await bodyFor('16:9'))['size'], '1536x1024');
      expect((await bodyFor('9:16'))['size'], '1024x1536');
      expect((await bodyFor(null))['size'], '1024x1024');
      expect((await bodyFor('7:3'))['size'], '1024x1024',
          reason: 'an unrecognised ratio is the square, not a 400');
    });

    test('asks for exactly one', () async {
      expect((await bodyFor(null))['n'], 1);
    });
  });

  group('when it does not work', () {
    test('a rejected key says so, and is not reported as an outage', () async {
      final events = await run(answering('{"error":{}}', status: 401));
      expect(events.whereType<StepFailed>().single.reason,
          contains('key was rejected'));
    });

    test('a 200 with no picture is a failure, not a silent success', () async {
      // Otherwise the turn completes, nothing appears, and there is nothing to
      // read that says why.
      final events = await run(answering(jsonEncode({'data': []})));
      expect(events.whereType<StepCompleted>(), isEmpty);
      expect(events.whereType<StepFailed>().single.reason,
          contains('without a picture'));
    });

    test('a refused request names the provider, like the text path does',
        () async {
      final events = await run(
        MockClient((_) => throw Exception('Failed to fetch')),
        reach: () async => Reach.up,
      );
      expect(events.whereType<StepFailed>().single.reason,
          contains('may not allow calls from a web page'));
    });

    test('and being offline still says offline', () async {
      final events = await run(
        MockClient((_) => throw Exception('Failed to fetch')),
        reach: () async => Reach.down,
      );
      expect(events.whereType<StepFailed>().single.reason, contains('offline'));
    });
  });
}
