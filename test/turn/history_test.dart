import 'package:flutter_test/flutter_test.dart';
import 'package:shift/features/chat/turn_controller.dart';
import 'package:shift/providers/clients/anthropic_text.dart';
import 'package:shift/providers/clients/gemini_text.dart';
import 'package:shift/providers/clients/openai_text.dart';
import 'package:shift/shell/mode.dart';
import 'package:shift/turn/capability.dart';
import 'package:shift/turn/history.dart';
import 'package:shift/turn/plan_jobs.dart';
import 'package:shift/turn/turn_request.dart';

/// Continuing a conversation rather than starting one every message.
///
/// The reported symptom: "I can continue on the same conversation rather than
/// just get individual prompts with individual responses." Every turn built a
/// request containing exactly one message, so "make it shorter" arrived with
/// nothing to shorten and the model answered it the only way it could.
void main() {
  Exchange said(String asked, String answered) =>
      Exchange(asked: asked, answered: answered);

  group('what counts as already said', () {
    test('a completed exchange does', () {
      final items = <ChatItem>[
        const UserSaid('what is a sonnet'),
        Reply()
          ..write('Fourteen lines.')
          ..done = true,
      ];

      final history = exchangesFrom(items);
      expect(history, hasLength(1));
      expect(history.single.asked, 'what is a sonnet');
      expect(history.single.answered, 'Fourteen lines.');
    });

    test('a failed reply does not, and takes its question with it', () {
      // "No provider is set up" is the app talking, not the assistant. Sent
      // back as something the model said, it teaches the model to say it.
      final items = <ChatItem>[
        const UserSaid('what is a sonnet'),
        Reply()..failure = 'That key was rejected.',
      ];

      expect(exchangesFrom(items), isEmpty);
    });

    test('a reply that said nothing does not', () {
      // A turn that only made a picture. An empty assistant message would be a
      // claim about what was said, and nothing was.
      final items = <ChatItem>[
        const UserSaid('draw a flower'),
        Reply()..done = true,
      ];

      expect(exchangesFrom(items), isEmpty);
    });

    test('a stopped reply keeps what arrived', () {
      // It is genuinely what was said, and a follow-up about it should find it.
      final items = <ChatItem>[
        const UserSaid('tell me about sonnets'),
        Reply()
          ..write('A sonnet has fourteen')
          ..interrupted = true
          ..done = true,
      ];

      expect(exchangesFrom(items).single.answered, 'A sonnet has fourteen');
    });

    test('the question currently being asked is not in it', () {
      // The controller reads history *before* appending this turn, so the
      // trailing unanswered question is never there. Asserted here because the
      // failure — the model seeing the same question twice — is invisible.
      final items = <ChatItem>[
        const UserSaid('first'),
        Reply()
          ..write('answer')
          ..done = true,
        const UserSaid('second'),
      ];

      final history = exchangesFrom(items);
      expect(history, hasLength(1));
      expect(history.single.asked, 'first');
    });

    test('every entry has both halves, whatever the transcript looks like', () {
      // The invariant the whole pair shape exists for: Anthropic rejects two
      // messages with the same role in a row, so a half-exchange is a 400.
      final items = <ChatItem>[
        const UserSaid('one'),
        Reply()..failure = 'nope',
        const UserSaid('two'),
        Reply()
          ..write('yes')
          ..done = true,
        const UserSaid('three'),
        Reply()..done = true,
      ];

      for (final exchange in exchangesFrom(items)) {
        expect(exchange.asked, isNotEmpty);
        expect(exchange.answered, isNotEmpty);
      }
      expect(exchangesFrom(items), hasLength(1));
    });
  });

  group('what fits', () {
    test('a short conversation goes whole', () {
      final history = [said('a', '1'), said('b', '2')];
      expect(trimHistory(history), hasLength(2));
    });

    test('the most recent survive, not the first', () {
      // A follow-up refers to the end of a conversation. Dropping the end to
      // keep the beginning would be the wrong half.
      final history = [
        for (var i = 0; i < 30; i++) said('ask $i', 'answer $i'),
      ];

      final kept = trimHistory(history, maxExchanges: 3);
      expect(kept.map((e) => e.asked), ['ask 27', 'ask 28', 'ask 29']);
    });

    test('and a few enormous turns are bounded too', () {
      // Twenty turns is not the only way to spend a fortune: one pasted
      // document does it in two.
      final history = [
        said('a', 'x' * 20000),
        said('b', 'y' * 20000),
        said('c', 'z' * 20000),
      ];

      final kept = trimHistory(history, maxChars: 24000);
      expect(kept, hasLength(1));
      expect(kept.single.asked, 'c', reason: 'the most recent one');
    });

    test('one oversized turn is kept rather than everything dropped', () {
      // Sending a bare follow-up with no context at all is worse than one
      // expensive turn, and a message longer than the budget is the model's to
      // refuse rather than ours to silently discard.
      final history = [said('a', 'x' * 90000)];
      expect(trimHistory(history, maxChars: 1000), hasLength(1));
    });

    test('nothing at all is nothing, not an empty message', () {
      expect(trimHistory(const []), isEmpty);
    });
  });

  group('the planner', () {
    test('carries the conversation on the writing step', () {
      final graph = planJobs(TurnRequest(
        input: 'make it shorter',
        history: [said('write me a poem', 'Roses are red...')],
      ));

      final main = graph.steps.firstWhere((s) => s.needs == Capability.text);
      expect(main.history, hasLength(1));
      expect(main.history.single.asked, 'write me a poem');
    });

    test('and never on a picture', () {
      // A drawing model handed the last twenty things that were said draws
      // something nobody asked for.
      final graph = planJobs(TurnRequest(
        input: 'draw a pink flower',
        mode: AppMode.visual,
        history: [said('write me a poem', 'Roses are red...')],
      ));

      for (final step in graph.steps) {
        expect(step.needs, Capability.image);
        expect(step.history, isEmpty);
      }
    });

    test('does not let the conversation change what is made', () {
      // History is context, not routing. A picture earlier in the conversation
      // must not turn a later question into a second picture.
      final withPictureTalk = planJobs(TurnRequest(
        input: 'what did you mean by that',
        history: [said('draw me an image of a logo', 'Here it is.')],
      ));

      expect(
        withPictureTalk.steps.map((s) => s.needs),
        everyElement(Capability.text),
      );
    });
  });

  group('the wire', () {
    final history = [said('first question', 'first answer')];

    test('Anthropic alternates user and assistant, ending on the new ask', () {
      final body = AnthropicText.buildBody(
        model: 'claude-sonnet-5',
        instruction: 'follow up',
        history: history,
      );

      final messages = body['messages'] as List<dynamic>;
      expect(messages.map((m) => (m as Map)['role']),
          ['user', 'assistant', 'user']);
      expect(messages.last, contains('content'));

      // Roles must alternate: two `user` messages in a row is a 400.
      for (var i = 1; i < messages.length; i++) {
        expect((messages[i] as Map)['role'],
            isNot((messages[i - 1] as Map)['role']));
      }
    });

    test('Gemini calls the assistant `model`', () {
      final body = GeminiText.buildBody(
        instruction: 'follow up',
        history: history,
      );

      final contents = body['contents'] as List<dynamic>;
      expect(contents.map((m) => (m as Map)['role']), ['user', 'model', 'user']);
    });

    test('OpenAI keeps the system message first', () {
      // The system prompt is not part of the conversation and must not be
      // pushed behind it.
      final body = OpenAiText.buildBody(
        model: 'gpt-4o',
        instruction: 'follow up',
        system: 'be brief',
        history: history,
      );

      final messages = body['messages'] as List<dynamic>;
      expect(messages.map((m) => (m as Map)['role']),
          ['system', 'user', 'assistant', 'user']);
    });

    test('and with no history the request is exactly what it was', () {
      // The regression guard: every existing turn must be unchanged, or this
      // is not an addition, it is a rewrite of every request the app sends.
      for (final body in [
        AnthropicText.buildBody(model: 'claude-sonnet-5', instruction: 'hi'),
        OpenAiText.buildBody(model: 'gpt-4o', instruction: 'hi'),
      ]) {
        expect((body['messages'] as List).length, 1);
      }
      expect(
        (GeminiText.buildBody(instruction: 'hi')['contents'] as List).length,
        1,
      );
    });
  });
}
