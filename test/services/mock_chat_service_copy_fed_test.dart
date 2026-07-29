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

  test('write-and-narrate routes to Voice and returns a voice card whose '
      'transcript is the written script', () async {
    final events = await _send('write and narrate a welcome message');

    expect(events.whereType<RoutingDetected>().single.studioType,
        StudioType.voiceAvatarStudio);
    final result = events.whereType<StudioResultReady>().single.result;
    expect(result, isA<AudioResult>());
    final audio = result as AudioResult;
    expect(audio.kind, AudioKind.voice);
    expect(audio.transcript, isNotNull);
    expect(audio.transcript!.trim(), isNotEmpty);

    // The written script is shown as chat text; routing stays invisible.
    final text = events.whereType<MessageDelta>().map((e) => e.chunk).join();
    expect(text, isNot(contains('Studio')));
    expect(text, contains(audio.transcript!.split(' ').first));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('write-a-jingle routes to Music with a titled track', () async {
    final events = await _send('write a jingle for my bakery');
    expect(events.whereType<RoutingDetected>().single.studioType,
        StudioType.musicStudio);
    final result = events.whereType<StudioResultReady>().single.result;
    expect(result, isA<AudioResult>());
    expect((result as AudioResult).kind, AudioKind.music);
    expect(result.title, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('write-a-video-script routes to Video with the script as prompt',
      () async {
    final events = await _send('write a video script and make the video');
    expect(events.whereType<RoutingDetected>().single.studioType,
        StudioType.videoStudio);
    final result = events.whereType<StudioResultReady>().single.result;
    expect(result, isA<VideoResult>());
    expect((result as VideoResult).prompt.trim(), isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('narrating user-provided text (no write signal) stays a plain voice '
      'request, not a copy-fed combo', () async {
    final events = await _send('narrate this line for me please');
    final text = events.whereType<MessageDelta>().map((e) => e.chunk).join();
    // No Copy & Scripts handoff intro.
    expect(text.contains('Copy & Scripts to write'), isFalse);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
