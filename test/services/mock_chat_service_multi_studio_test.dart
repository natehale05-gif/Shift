import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/data/models/artifact.dart';
import 'package:shift_ai/data/models/conversation.dart';
import 'package:shift_ai/data/models/studio_type.dart';
import 'package:shift_ai/services/chat_service.dart';
import 'package:shift_ai/services/mock_chat_service.dart';

Conversation _empty() => Conversation(
      id: 'c1',
      title: 'Test',
      createdAt: DateTime(2026, 7, 20),
      updatedAt: DateTime(2026, 7, 20),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a fresh "website with several photos" request routes to Code '
      'Studio and comes back with the gallery already embedded', () async {
    final events = await MockChatService()
        .sendMessage(
          conversation: _empty(),
          userInput: 'build me a dog treat website with several photos',
        )
        .toList();

    expect(events.whereType<RoutingDetected>().single.studioType,
        StudioType.codeStudio);

    final created = events.whereType<ArtifactCreated>().single.artifact;
    expect(created.kind, ArtifactKind.html);
    expect('<img'.allMatches(created.latest.content).length, 3);

    // The images are woven into the one artifact, not shown as separate
    // inline image cards.
    expect(events.whereType<StudioResultReady>(), isEmpty);

    // Routing is invisible (like Claude): the visible text never names a studio.
    final text = events.whereType<MessageDelta>().map((e) => e.chunk).join();
    expect(text, isNot(contains('Studio')));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('an explicit photo count is honored', () async {
    final events = await MockChatService()
        .sendMessage(
          conversation: _empty(),
          userInput: 'build a portfolio page with 2 photos',
        )
        .toList();

    final created = events.whereType<ArtifactCreated>().single.artifact;
    expect('<img'.allMatches(created.latest.content).length, 2);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a plain page request with no visual keyword is unaffected', () async {
    final events = await MockChatService()
        .sendMessage(
          conversation: _empty(),
          userInput: 'build me a landing page for my bakery',
        )
        .toList();

    final created = events.whereType<ArtifactCreated>().single.artifact;
    expect(created.latest.content.contains('<img'), isFalse);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
