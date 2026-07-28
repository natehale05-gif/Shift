import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/data/models/artifact.dart';
import 'package:shift_ai/data/models/chat_message.dart';
import 'package:shift_ai/data/models/conversation.dart';
import 'package:shift_ai/data/models/studio_request.dart';
import 'package:shift_ai/data/models/studio_type.dart';
import 'package:shift_ai/services/artifact_composition.dart';
import 'package:shift_ai/services/chat_service.dart';
import 'package:shift_ai/services/interactive_artifacts.dart';
import 'package:shift_ai/services/studio_composition.dart';
import 'package:shift_ai/turn/plan_turn.dart';
import 'package:shift_ai/turn/turn_input.dart';
import 'package:shift_ai/turn/turn_plan.dart';

/// These assert the *decision* half of a turn. Because [planTurn] is pure they
/// need no streaming, no fake HTTP clients and no timeouts — the equivalent
/// coverage used to require driving a whole service and waiting on artificial
/// delays.
Conversation _empty() => Conversation(
      id: 'c1',
      title: 'Test',
      createdAt: DateTime(2026, 7, 20),
      updatedAt: DateTime(2026, 7, 20),
    );

Conversation _withHtmlArtifact() => Conversation(
      id: 'c1',
      title: 'Test',
      createdAt: DateTime(2026, 7, 20),
      updatedAt: DateTime(2026, 7, 20),
      artifacts: [
        Artifact(
          id: 'art1',
          conversationId: 'c1',
          title: 'Bakery landing page',
          kind: ArtifactKind.html,
          versions: [
            ArtifactVersion(
              content: '<!DOCTYPE html><html><body><h1>Northbound'
                  '</h1></body></html>',
              createdAt: DateTime(2026, 7, 20),
            ),
          ],
        ),
      ],
      messages: [
        ChatMessage(
          id: 'u0',
          conversationId: 'c1',
          role: MessageRole.user,
          text: 'build me a landing page for my bakery',
          timestamp: DateTime(2026, 7, 20),
        ),
        ChatMessage(
          id: 'a0',
          conversationId: 'c1',
          role: MessageRole.assistant,
          text: 'Here you go.',
          studioType: StudioType.codeStudio,
          timestamp: DateTime(2026, 7, 20),
        ),
      ],
    );

TurnPlan _plan(
  String input, {
  Conversation? conversation,
  StudioRequest? structured,
  ChatOptions options = ChatOptions.none,
}) =>
    planTurn(TurnInput(
      conversation: conversation ?? _empty(),
      userInput: input,
      structuredRequest: structured,
      options: options,
    ));

void main() {
  group('interactive artifacts', () {
    test('a recipe request is an interactive turn built by Code Studio', () {
      final turn = _plan('make a recipe card for banana bread');
      expect(turn, isA<InteractiveTurn>());
      expect((turn as InteractiveTurn).kind, InteractiveKind.recipe);
      expect(turn.studio, StudioType.codeStudio);
    });

    test('quizzes and flashcards are detected too', () {
      expect((_plan('make a quiz about the solar system') as InteractiveTurn)
          .kind, InteractiveKind.quiz);
      expect((_plan('make flashcards for spanish verbs') as InteractiveTurn)
          .kind, InteractiveKind.flashcards);
    });

    test('interactive detection outranks a diagram keyword', () {
      // "flow" appears in both vocabularies; the interactive branch is first.
      final turn = _plan('make a checklist for my sign-up flow');
      expect(turn, isA<InteractiveTurn>());
    });
  });

  group('diagrams', () {
    test('a flowchart request is a diagram turn', () {
      expect(_plan('draw a flowchart of a sign-up flow'), isA<DiagramTurn>());
    });

    test('mind maps and sequence diagrams too', () {
      expect(_plan('make a mind map of the roman empire'), isA<DiagramTurn>());
      expect(_plan('sequence diagram for checkout'), isA<DiagramTurn>());
    });
  });

  group('research and search', () {
    test('the deep-research option forces a research turn', () {
      final turn = _plan('tell me about fusion',
          options: const ChatOptions(deepResearch: true));
      expect(turn, isA<DeepResearchTurn>());
    });

    test('the phrase "deep research" alone is enough', () {
      expect(_plan('do deep research on fusion'), isA<DeepResearchTurn>());
    });

    test('research outranks web search', () {
      final turn = _plan('search the web and do deep research on fusion',
          options: const ChatOptions(webSearch: true));
      expect(turn, isA<DeepResearchTurn>());
    });

    test('the web-search option yields a search turn for a general question',
        () {
      final turn = _plan('what happened in the news today',
          options: const ChatOptions(webSearch: true));
      expect(turn, isA<WebSearchTurn>());
    });
  });

  group('composition', () {
    test('adding a hero image to an existing site is an edit, routed to Image',
        () {
      final turn = _plan('add a hero image to the website',
          conversation: _withHtmlArtifact());
      expect(turn, isA<StudioTurn>());
      final studioTurn = turn as StudioTurn;
      expect(turn.studio, StudioType.imageStudio);
      expect(studioTurn.composeTarget?.id, 'art1');
      expect(studioTurn.composeKind, ArtifactMediaKind.image);
    });

    test('adding music to an existing site embeds audio', () {
      final turn = _plan('add background music to the website',
          conversation: _withHtmlArtifact()) as StudioTurn;
      expect(turn.composeTarget?.id, 'art1');
      expect(turn.composeKind, ArtifactMediaKind.audio);
    });

    test('a standalone image request is not an edit', () {
      final turn = _plan('make me a completely separate poster for a concert',
          conversation: _withHtmlArtifact()) as StudioTurn;
      expect(turn.composeTarget, isNull);
      expect(turn.studio, StudioType.imageStudio);
    });

    test('a page build routes to Code Studio and carries its contributors', () {
      final turn = _plan('build a landing page for my bakery with photos');
      expect(turn, isA<StudioTurn>());
      expect(turn.studio, StudioType.codeStudio);
      expect((turn as StudioTurn).contributors, contains(StudioType.imageStudio));
    });

    test('copy-fed media routes to the host studio', () {
      final turn = _plan('write a script about coffee and narrate it');
      expect(turn, isA<CopyFedTurn>());
      expect((turn as CopyFedTurn).kind, isNot(CompositionKind.none));
    });
  });

  group('avatar', () {
    test('an avatar request becomes a talking-head media pair', () {
      final turn = _plan('make an avatar video of me saying hello');
      if (turn is MediaPairTurn) {
        expect(turn.kind, CompositionKind.talkingAvatar);
      } else {
        // Routing may classify it as a pair via composition instead; either
        // way it must not fall through to a plain studio turn.
        expect(turn, isA<MediaPairTurn>());
      }
    });
  });

  group('structured requests and clarification', () {
    test('a structured request keeps its own studio and is never re-planned',
        () {
      final turn = _plan(
        'a poster',
        structured: const ImageRequest(prompt: 'a poster', aspectRatio: '1:1',
            stylePreset: 'photo', count: 1),
      );
      expect(turn, isA<StudioTurn>());
      expect(turn.studio, StudioType.imageStudio);
      expect((turn as StudioTurn).structuredRequest, isNotNull);
      // Composition and interactive detection are both skipped.
      expect(turn.composeTarget, isNull);
      expect(turn.contributors, isEmpty);
    });

    test('a structured request is not reinterpreted as an interactive artifact',
        () {
      // Free text like this would be a recipe card; as a structured image
      // request it must stay an image.
      final turn = _plan(
        'a recipe card for banana bread',
        structured:
            const ImageRequest(prompt: 'a recipe card',
                aspectRatio: '1:1', stylePreset: 'photo', count: 1),
      );
      expect(turn, isA<StudioTurn>());
      expect(turn.studio, StudioType.imageStudio);
    });

    test('answering our clarifying question continues the same studio and '
        'merges the prompts', () {
      // By the time a turn is planned the store has already appended this
      // turn's user message and an empty streaming placeholder, so the prior
      // exchange sits third and fourth from the end. findPendingClarification
      // relies on exactly that layout.
      final convo = Conversation(
        id: 'c1',
        title: 'Test',
        createdAt: DateTime(2026, 7, 20),
        updatedAt: DateTime(2026, 7, 20),
        messages: [
          ChatMessage(
            id: 'u0',
            conversationId: 'c1',
            role: MessageRole.user,
            text: 'make me a logo',
            timestamp: DateTime(2026, 7, 20),
          ),
          ChatMessage(
            id: 'a0',
            conversationId: 'c1',
            role: MessageRole.assistant,
            text: 'What colour palette should it use?',
            studioType: StudioType.imageStudio,
            timestamp: DateTime(2026, 7, 20),
          ),
          ChatMessage(
            id: 'u1',
            conversationId: 'c1',
            role: MessageRole.user,
            text: 'navy blue',
            timestamp: DateTime(2026, 7, 20),
          ),
          ChatMessage(
            id: 'a1',
            conversationId: 'c1',
            role: MessageRole.assistant,
            text: '',
            timestamp: DateTime(2026, 7, 20),
          ),
        ],
      );
      final turn = _plan('navy blue', conversation: convo);
      expect(turn.studio, StudioType.imageStudio);
      expect(turn.isAnsweringClarification, isTrue);
      expect(turn.effectiveInput, contains('navy blue'));
      expect(turn.effectiveInput, contains('make me a logo'));
    });
  });

  group('canonical branch order', () {
    // Before the pipeline existed, the live service evaluated deep research
    // BEFORE interactive detection while the demo service did the opposite, so
    // the same prompt could answer two different ways depending on whether the
    // user had keys. planTurn's order is now the single answer, and these pin
    // it. Changing either expectation is a deliberate product decision, not a
    // refactor.
    test('interactive detection outranks the deep-research toggle', () {
      final turn = _plan('make a recipe card for banana bread',
          options: const ChatOptions(deepResearch: true));
      expect(turn, isA<InteractiveTurn>(),
          reason: 'demo mode has always answered this with a recipe card; '
              'live mode now agrees');
    });

    test('a diagram request outranks the deep-research toggle', () {
      final turn = _plan('draw a flowchart of a sign-up flow',
          options: const ChatOptions(deepResearch: true));
      expect(turn, isA<DiagramTurn>());
    });

    test('deep research still outranks plain web search', () {
      final turn = _plan('what is happening with fusion',
          options: const ChatOptions(deepResearch: true, webSearch: true));
      expect(turn, isA<DeepResearchTurn>());
    });
  });

  test('a plain question is an ordinary middleware studio turn', () {
    final turn = _plan('hello there, tell me something');
    expect(turn, isA<StudioTurn>());
    expect(turn.studio, StudioType.middleware);
    expect(turn.isAnsweringClarification, isFalse);
    expect(turn.effectiveInput, 'hello there, tell me something');
  });
}
