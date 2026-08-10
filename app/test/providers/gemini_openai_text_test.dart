import 'package:flutter_test/flutter_test.dart';
import 'package:shift/providers/access.dart';
import 'package:shift/providers/clients/gemini_text.dart';
import 'package:shift/providers/clients/openai_text.dart';
import 'package:shift/providers/registry.dart';
import 'package:shift/providers/streaming/sse_client.dart';
import 'package:shift/turn/job_output.dart';
import 'package:shift/turn/turn_event.dart';

/// Two wires that are not Anthropic's, and the differences that would each
/// look like the model being broken rather than the client being wrong.
Stream<SseEvent> replay(List<String> frames) => Stream.fromIterable(
      frames.map((f) => SseEvent(event: '', data: f)),
    );

void main() {
  group('Gemini', () {
    Future<List<TurnEvent>> run(List<String> frames) =>
        GeminiText.mapEvents(replay(frames), stepId: 's').toList();

    test('text arrives from candidates.content.parts', () async {
      final events = await run([
        '{"candidates":[{"content":{"parts":[{"text":"Hello"}]}}]}',
        '{"candidates":[{"content":{"parts":[{"text":" there"}]}}]}',
      ]);

      expect(events.whereType<TextDelta>().map((e) => e.text),
          ['Hello', ' there']);
      expect((events.whereType<StepCompleted>().single.output as TextOutput)
          .text, 'Hello there');
    });

    test('a chunk with no parts is skipped, not fatal', () async {
      final events = await run([
        '{"candidates":[{"finishReason":"STOP"}]}',
        '{"candidates":[{"content":{"parts":[{"text":"ok"}]}}]}',
      ]);
      expect(events.whereType<TextDelta>().single.text, 'ok');
    });

    test('grounding becomes sources, each one once', () async {
      // The same source is cited by several chunks; a list would repeat it
      // once per sentence it supported.
      const chunk = '{"candidates":[{"content":{"parts":[{"text":"x"}]},'
          '"groundingMetadata":{"groundingChunks":['
          '{"web":{"uri":"https://a.example","title":"A"}}]}}]}';
      final events = await run([chunk, chunk]);

      final found = events.whereType<CitationsFound>().single.citations;
      expect(found, hasLength(1));
      expect(found.single.title, 'A');
    });

    test('MAX_TOKENS completes and says it stopped early', () async {
      final events = await run([
        '{"candidates":[{"content":{"parts":[{"text":"half"}]},'
            '"finishReason":"MAX_TOKENS"}]}',
      ]);

      expect(events.whereType<StepCompleted>(), isNotEmpty,
          reason: 'what arrived is still worth having');
      final soft = events.whereType<StepFailed>().single;
      expect(soft.blocksDependents, isFalse);
      expect(soft.reason, contains('length limit'));
    });

    test('the key rides in the query string, and only when direct', () {
      // Gemini's own scheme for browsers. A managed call must not carry it —
      // the proxy sets `x-goog-api-key`, which keeps it out of every access
      // log between here and Google.
      final direct = GeminiText.target(const DirectKey('AIza-x'), 'gemini-x');
      expect(direct.uri.queryParameters['key'], 'AIza-x');
      expect(direct.uri.queryParameters['alt'], 'sse',
          reason: 'without alt=sse the endpoint answers once at the end, '
              'which looks exactly like a very slow model');

      final managed = GeminiText.target(
        ManagedAccess(base: Uri.parse('https://p.example/gemini'),
            headers: const {'authorization': 'Bearer t'}),
        'gemini-x',
      );
      expect(managed.uri.queryParameters.containsKey('key'), isFalse);
      expect(managed.headers['authorization'], 'Bearer t');
    });

    test('the system prompt is its own field', () async {
      // Sent as a `user` turn it becomes part of the conversation and the
      // model answers it instead of obeying it.
      final body = GeminiText.buildBody(instruction: 'hi', system: 'be terse');
      expect(body['systemInstruction'], isNotNull);
      expect(body['contents'], hasLength(1));
    });
  });

  group('OpenAI-compatible', () {
    Future<List<TurnEvent>> run(List<String> frames) =>
        OpenAiText.mapEvents(replay(frames), stepId: 's').toList();

    test('text arrives from choices.delta.content', () async {
      final events = await run([
        '{"choices":[{"delta":{"role":"assistant"}}]}',
        '{"choices":[{"delta":{"content":"Hel"}}]}',
        '{"choices":[{"delta":{"content":"lo"}}]}',
        '[DONE]',
      ]);

      expect(events.whereType<TextDelta>().map((e) => e.text), ['Hel', 'lo']);
      expect((events.whereType<StepCompleted>().single.output as TextOutput)
          .text, 'Hello');
    });

    test('[DONE] ends the stream, and nothing after it is reply text',
        () async {
      // It is not JSON, so decoding it throws — which, caught as "malformed",
      // happens to look harmless. The difference that matters is that `[DONE]`
      // means the stream is *over*: anything a provider or proxy appends after
      // it is not part of the answer.
      //
      // Written first as "does not fail", which passed with the guard removed
      // and was therefore a check that could not fail.
      final events = await run([
        '{"choices":[{"delta":{"content":"real"}}]}',
        '[DONE]',
        '{"choices":[{"delta":{"content":" trailing junk"}}]}',
      ]);

      expect((events.whereType<StepCompleted>().single.output as TextOutput)
          .text, 'real');
      expect(events.whereType<StepFailed>(), isEmpty);
    });

    test('finish_reason length says it stopped early', () async {
      final events = await run([
        '{"choices":[{"delta":{"content":"half"},"finish_reason":"length"}]}',
      ]);
      final soft = events.whereType<StepFailed>().single;
      expect(soft.blocksDependents, isFalse);
    });

    test('the key is a bearer token, and only when direct', () {
      final direct = OpenAiText.target(
          const DirectKey('sk-x'), 'https://api.example.com/v1');
      expect(direct.headers['authorization'], 'Bearer sk-x');
      expect(direct.uri.toString(), 'https://api.example.com/v1/chat/completions');

      final managed = OpenAiText.target(
        ManagedAccess(base: Uri.parse('https://p.example/openai'),
            headers: const {'authorization': 'Bearer session'}),
        'https://api.example.com/v1',
      );
      expect(managed.uri.host, 'p.example');
      expect(managed.headers['authorization'], 'Bearer session');
    });

    test('a trailing slash on the base url does not double up', () {
      expect(OpenAiText.endpoint('https://x.example/v1/').toString(),
          'https://x.example/v1/chat/completions');
    });
  });

  test('every provider that is not Anthropic or Gemini has a base url', () {
    // The executor dispatches on the wire, so a provider in the table with no
    // endpoint is one the router can pick and nothing can call. Cheaper to
    // assert here than to discover as a failed turn.
    for (final provider in kProviders) {
      if (provider.id == 'anthropic' || provider.id == 'gemini') continue;
      expect(provider.baseUrl, isNotNull, reason: provider.id);
    }
  });
}
