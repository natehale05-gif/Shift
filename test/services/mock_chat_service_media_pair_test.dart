import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/data/models/conversation.dart';
import 'package:shift_ai/data/models/studio_result.dart';
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

  test('a talking avatar returns a portrait image AND a voice card in one '
      'reply', () async {
    final events = await _send('make a talking avatar that says hello');

    expect(events.whereType<RoutingDetected>().single.studioType,
        StudioType.avatarStudio);

    // The portrait renders as an inline image (ImageGenerated -> ImageBlock).
    final image = events.whereType<ImageGenerated>().single;
    expect(image.pngBytes, isNotEmpty);

    // The voice narration is the studio-result card.
    final result = events.whereType<StudioResultReady>().single.result;
    expect(result, isA<AudioResult>());
    expect((result as AudioResult).kind, AudioKind.voice);
    expect(result.transcript, isNotNull);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('scored narration returns a single music-bed card (no separate '
      'image)', () async {
    final events = await _send('narrate this line over background music');

    expect(events.whereType<ImageGenerated>(), isEmpty);
    final result = events.whereType<StudioResultReady>().single.result;
    expect(result, isA<AudioResult>());
    final audio = result as AudioResult;
    expect(audio.kind, AudioKind.music);
    expect(audio.transcript, isNotNull);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a plain avatar request still pairs image + voice', () async {
    final events = await _send('make me a talking avatar');
    expect(events.whereType<ImageGenerated>(), hasLength(1));
    expect(events.whereType<StudioResultReady>(), hasLength(1));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
