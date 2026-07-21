import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/models/artifact.dart';
import 'package:shift_ai/models/chat_message.dart';
import 'package:shift_ai/models/conversation.dart';
import 'package:shift_ai/models/studio_type.dart';
import 'package:shift_ai/services/chat_service.dart';
import 'package:shift_ai/services/mock_chat_service.dart';

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
              content: '<!DOCTYPE html><html><body><h1>Northbound '
                  'Bakery</h1></body></html>',
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('adding a hero image to an existing site updates the artifact '
      'instead of producing a standalone image card', () async {
    final events = await MockChatService()
        .sendMessage(
          conversation: _withHtmlArtifact(),
          userInput: 'add a hero image to the website',
        )
        .toList();

    expect(events.whereType<RoutingDetected>().single.studioType,
        StudioType.imageStudio);

    final updated = events.whereType<ArtifactUpdated>().single.artifact;
    expect(updated.id, 'art1');
    expect(updated.versions, hasLength(2));
    expect(updated.latest.content, contains('<img'));
    expect(updated.latest.content, contains('data:image/png;base64,'));

    // The image is woven into the artifact, not shown as its own card.
    expect(events.whereType<StudioResultReady>(), isEmpty);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a standalone image request in the same conversation is left alone',
      () async {
    final events = await MockChatService()
        .sendMessage(
          conversation: _withHtmlArtifact(),
          userInput: 'make me a completely separate poster for a concert',
        )
        .toList();

    expect(events.whereType<StudioResultReady>(), hasLength(1));
    expect(events.whereType<ArtifactUpdated>(), isEmpty);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('adding background music to an existing site embeds an audio player, '
      'not a standalone audio card', () async {
    final events = await MockChatService()
        .sendMessage(
          conversation: _withHtmlArtifact(),
          userInput: 'add background music to the website',
        )
        .toList();

    final updated = events.whereType<ArtifactUpdated>().single.artifact;
    expect(updated.id, 'art1');
    expect(updated.versions, hasLength(2));
    expect(updated.latest.content, contains('<audio controls'));
    expect(updated.latest.content, contains('data:audio/wav;base64,'));
    // Woven into the page, not shown as its own card.
    expect(events.whereType<StudioResultReady>(), isEmpty);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('adding a video to an existing site embeds a video block, not a '
      'standalone video card', () async {
    final events = await MockChatService()
        .sendMessage(
          conversation: _withHtmlArtifact(),
          userInput: 'add a video to the website',
        )
        .toList();

    final updated = events.whereType<ArtifactUpdated>().single.artifact;
    expect(updated.id, 'art1');
    expect(updated.versions, hasLength(2));
    expect(updated.latest.content, contains('Simulated video'));
    expect(updated.latest.content, contains('data:image/png;base64,'));
    expect(events.whereType<StudioResultReady>(), isEmpty);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
