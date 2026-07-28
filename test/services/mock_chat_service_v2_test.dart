import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/data/models/artifact.dart';
import 'package:shift_ai/data/models/conversation.dart';
import 'package:shift_ai/turn/chat_service.dart';
import 'package:shift_ai/turn/backends/mock_backend.dart';

Conversation _conversation({List<Artifact> artifacts = const []}) =>
    Conversation(
      id: 'c1',
      title: 'Test',
      createdAt: DateTime(2026, 7, 19),
      updatedAt: DateTime(2026, 7, 19),
      artifacts: artifacts,
    );

Future<List<ChatEvent>> _collect(String input,
    {Conversation? conversation, ChatOptions options = ChatOptions.none}) {
  return MockChatService()
      .sendMessage(
        conversation: conversation ?? _conversation(),
        userInput: input,
        options: options,
      )
      .toList();
}

void main() {
  test('every turn streams thinking before the reply and reports usage',
      () async {
    final events = await _collect('hello there');
    final thinkingIndex = events.indexWhere((e) => e is ThinkingDelta);
    final textIndex = events.indexWhere((e) => e is MessageDelta);

    expect(thinkingIndex, isNot(-1));
    expect(textIndex, isNot(-1));
    expect(thinkingIndex, lessThan(textIndex));
    expect(events.whereType<UsageReported>(), hasLength(1));
    expect(events.last, isA<MessageComplete>().having((_) => true, 'x', true));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('search-shaped prompt runs the web-search tool and cites sources',
      () async {
    final events = await _collect('what is the latest news on AI chips');

    final started = events.whereType<ToolUseStarted>().single;
    expect(started.tool, 'web_search');
    final finished = events.whereType<ToolUseFinished>().single;
    expect(finished.id, started.id);
    expect(events.whereType<CitationsReady>().single.citations, hasLength(3));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('landing-page prompt creates an HTML artifact', () async {
    final events = await _collect('build me a landing page for my bakery');

    final created = events.whereType<ArtifactCreated>().single;
    expect(created.artifact.kind, ArtifactKind.html);
    expect(created.artifact.latest.content, contains('<!DOCTYPE html>'));
    expect(events.whereType<ArtifactUpdated>(), isEmpty);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('plain code prompt creates a code artifact', () async {
    final events = await _collect('write a python function to parse dates');

    final created = events.whereType<ArtifactCreated>().single;
    expect(created.artifact.kind, ArtifactKind.code);
    expect(created.artifact.language, 'python');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('code follow-up in a conversation with an artifact revises it',
      () async {
    final existing = Artifact(
      id: 'a1',
      conversationId: 'c1',
      title: 'bakery landing page',
      kind: ArtifactKind.html,
      versions: [
        ArtifactVersion(
          content: '<html>v1</html>',
          createdAt: DateTime(2026, 7, 19),
        ),
      ],
    );
    final events = await _collect(
      'change the code so the button is red',
      conversation: _conversation(artifacts: [existing]),
    );

    final updated = events.whereType<ArtifactUpdated>().single;
    expect(updated.artifact.id, 'a1');
    expect(updated.artifact.versions, hasLength(2));
    expect(events.whereType<ArtifactCreated>(), isEmpty);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('deep research option walks planning/searching/synthesizing stages',
      () async {
    final events = await _collect(
      'the economics of vertical farming',
      options: const ChatOptions(deepResearch: true),
    );

    final stages = events
        .whereType<DeepResearchProgress>()
        .map((e) => e.stage)
        .toList();
    expect(stages.first, 'planning');
    expect(stages, contains('searching'));
    expect(stages.last, 'synthesizing');
    expect(events.whereType<CitationsReady>(), hasLength(1));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
