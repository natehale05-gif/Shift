import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/data/models/conversation.dart';
import 'package:shift_ai/data/models/studio_type.dart';
import 'package:shift_ai/turn/chat_service.dart';
import 'package:shift_ai/turn/backends/mock_backend.dart';

Conversation _empty() => Conversation(
      id: 'c1',
      title: 'Test',
      createdAt: DateTime(2026, 7, 20),
      updatedAt: DateTime(2026, 7, 20),
    );

Future<List<ChatEvent>> _send(String prompt) =>
    MockChatService().sendMessage(conversation: _empty(), userInput: prompt).toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a recipe card is built as an interactive HTML artifact by Code Studio',
      () async {
    final events = await _send('make an interactive recipe card for lasagna');
    expect(events.whereType<RoutingDetected>().single.studioType,
        StudioType.codeStudio);
    final artifact = events.whereType<ArtifactCreated>().single.artifact;
    expect(artifact.latest.content, contains('<script>'));
    expect(artifact.latest.content, contains('class="ing"'));
    expect(artifact.latest.content, contains('Start timer'));
    // No standalone studio-result card — the interactive artifact is the deliverable.
    expect(events.whereType<StudioResultReady>(), isEmpty);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a quiz is an interactive artifact with scoring', () async {
    final events = await _send('build a quiz about the solar system');
    final artifact = events.whereType<ArtifactCreated>().single.artifact;
    expect(artifact.latest.content, contains('Check answers'));
    expect(artifact.latest.content, contains('data-answer='));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('flashcards and checklists route to interactive artifacts too', () async {
    final flash = await _send('flashcards for spanish verbs');
    expect(flash.whereType<ArtifactCreated>().single.artifact.latest.content,
        contains('const cards=['));
    final list = await _send('a packing list for a camping trip');
    expect(list.whereType<ArtifactCreated>().single.artifact.latest.content,
        contains('id="fill"'));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
