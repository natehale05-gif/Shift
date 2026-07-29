import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shift_ai/data/models/chat_message.dart';
import 'package:shift_ai/data/models/conversation.dart';
import 'package:shift_ai/data/models/studio_type.dart';
import 'package:shift_ai/turn/chat_service.dart';
import 'package:shift_ai/data/persistence/persistence_service.dart';
import 'package:shift_ai/providers/clients/gemini_client.dart';
import 'package:shift_ai/turn/backends/live_backend.dart';
import 'package:shift_ai/providers/router/model_router.dart';
import 'package:shift_ai/data/stores/api_keys_store.dart';

/// Always returns [forced], so tests can prove the pending-clarification
/// override takes precedence over (or is bypassed by) the router.
class _ForcedRouter extends ModelRouter {
  final ChatRoute forced;
  _ForcedRouter(this.forced);

  @override
  Future<ChatRoute> route({
    required String input,
    String? anthropicKey,
    String? geminiKey,
  }) async =>
      forced;
}

class _RecordingGeminiClient extends GeminiClient {
  String? lastImagePrompt;

  @override
  Stream<ChatEvent> generateImage({
    required String apiKey,
    required String prompt,
  }) async* {
    lastImagePrompt = prompt;
    yield ImageGenerated(pngBytes: Uint8List(0), alt: 'test');
    yield const MessageComplete();
  }
}

Conversation _freshConversation(String userInput) => Conversation(
      id: 'c1',
      title: 'x',
      createdAt: DateTime(2026, 7, 20),
      updatedAt: DateTime(2026, 7, 20),
      messages: [
        ChatMessage(
          id: 'u1',
          conversationId: 'c1',
          role: MessageRole.user,
          text: userInput,
          timestamp: DateTime(2026, 7, 20),
        ),
        ChatMessage(
          id: 'a1',
          conversationId: 'c1',
          role: MessageRole.assistant,
          text: '',
          status: MessageStatus.streaming,
          timestamp: DateTime(2026, 7, 20),
        ),
      ],
    );

Conversation _conversationAfterQuestion(String question) => Conversation(
      id: 'c1',
      title: 'x',
      createdAt: DateTime(2026, 7, 20),
      updatedAt: DateTime(2026, 7, 20),
      messages: [
        ChatMessage(
          id: 'u1',
          conversationId: 'c1',
          role: MessageRole.user,
          text: 'make me a logo',
          timestamp: DateTime(2026, 7, 20),
        ),
        ChatMessage(
          id: 'a1',
          conversationId: 'c1',
          role: MessageRole.assistant,
          text: question,
          studioType: StudioType.imageStudio,
          timestamp: DateTime(2026, 7, 20),
        ),
        ChatMessage(
          id: 'u2',
          conversationId: 'c1',
          role: MessageRole.user,
          text: 'navy blue',
          timestamp: DateTime(2026, 7, 20),
        ),
        ChatMessage(
          id: 'a2',
          conversationId: 'c1',
          role: MessageRole.assistant,
          text: '',
          status: MessageStatus.streaming,
          timestamp: DateTime(2026, 7, 20),
        ),
      ],
    );

Future<ApiKeysStore> _liveGeminiKeys() async {
  SharedPreferences.setMockInitialValues({});
  final keys = ApiKeysStore(persistence: PersistenceService());
  await keys.load();
  await keys.setGeminiKey('test-gemini-key');
  return keys;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a terse fresh image prompt asks instead of calling Gemini',
      () async {
    final keys = await _liveGeminiKeys();
    final gemini = _RecordingGeminiClient();
    final service = RealChatService(
      keys: keys,
      geminiClient: gemini,
      router: _ForcedRouter(ChatRoute.imageGen),
    );

    final events = await service
        .sendMessage(
          conversation: _freshConversation('make me a logo'),
          userInput: 'make me a logo',
        )
        .toList();

    expect(events.whereType<RoutingDetected>().single.studioType,
        StudioType.imageStudio);
    expect(
      events.whereType<MessageDelta>().single.chunk.trimRight(),
      endsWith('?'),
    );
    expect(gemini.lastImagePrompt, isNull);
    expect(events.last, isA<MessageComplete>());
  });

  test('answering the clarifying question bypasses the router and merges '
      'into the real Gemini call', () async {
    final keys = await _liveGeminiKeys();
    final gemini = _RecordingGeminiClient();
    // Deliberately wrong: proves the pending-clarification override wins,
    // not this router.
    final service = RealChatService(
      keys: keys,
      geminiClient: gemini,
      router: _ForcedRouter(ChatRoute.chat),
    );

    final question = 'Happy to create that — what\'s the subject or brand?';
    final events = await service
        .sendMessage(
          conversation: _conversationAfterQuestion(question),
          userInput: 'navy blue',
        )
        .toList();

    expect(gemini.lastImagePrompt, 'make me a logo navy blue');
    expect(events.whereType<ImageGenerated>(), hasLength(1));
  });

  test('a descriptive fresh image prompt generates without asking',
      () async {
    final keys = await _liveGeminiKeys();
    final gemini = _RecordingGeminiClient();
    final service = RealChatService(
      keys: keys,
      geminiClient: gemini,
      router: _ForcedRouter(ChatRoute.imageGen),
    );

    const prompt = 'a minimalist navy blue logo for a coffee shop called '
        'Northbound';
    final events = await service
        .sendMessage(
          conversation: _freshConversation(prompt),
          userInput: prompt,
        )
        .toList();

    expect(gemini.lastImagePrompt, prompt);
    expect(events.whereType<ImageGenerated>(), hasLength(1));
  });
}
