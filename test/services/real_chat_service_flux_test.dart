import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shift_ai/models/chat_message.dart';
import 'package:shift_ai/models/conversation.dart';
import 'package:shift_ai/models/studio_request.dart';
import 'package:shift_ai/services/chat_service.dart';
import 'package:shift_ai/services/persistence_service.dart';
import 'package:shift_ai/services/providers/flux_client.dart';
import 'package:shift_ai/services/real_chat_service.dart';
import 'package:shift_ai/services/router/model_router.dart';
import 'package:shift_ai/state/api_keys_store.dart';

/// Forces the image route so the test exercises Auto's provider dispatch
/// rather than the classifier.
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

/// A Flux client that records the prompt and returns a canned image, so the
/// test proves the image route reached Flux without any network.
class _FakeFlux extends FluxClient {
  int calls = 0;
  String? seenPrompt;
  String? seenKey;

  @override
  Stream<ChatEvent> generateImage({
    required String apiKey,
    required String prompt,
    String model = 'flux-pro-1.1',
    int width = 1024,
    int height = 768,
  }) async* {
    calls++;
    seenKey = apiKey;
    seenPrompt = prompt;
    yield ImageGenerated(pngBytes: Uint8List.fromList([9, 9, 9]), alt: 'x');
    yield const MessageComplete();
  }
}

Conversation _fresh(String input) => Conversation(
      id: 'c1',
      title: 'x',
      createdAt: DateTime(2026, 7, 20),
      updatedAt: DateTime(2026, 7, 20),
      messages: [
        ChatMessage(
          id: 'u1',
          conversationId: 'c1',
          role: MessageRole.user,
          text: input,
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

Future<ApiKeysStore> _keys(Map<String, String> keys) async {
  SharedPreferences.setMockInitialValues({});
  final store = ApiKeysStore(persistence: PersistenceService());
  await store.load();
  for (final e in keys.entries) {
    await store.setKey(e.key, e.value);
  }
  return store;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a structured Image Studio request with only a Flux key runs on Flux',
      () async {
    final keys = await _keys({'flux': 'flux-key'});
    final flux = _FakeFlux();
    final service = RealChatService(keys: keys, fluxClient: flux);

    final events = await service
        .sendMessage(
          conversation: _fresh('a poster'),
          userInput: 'a poster',
          structuredRequest: const ImageRequest(
            prompt: 'a neon poster of a fox',
            aspectRatio: '1:1',
            stylePreset: 'neon',
            count: 1,
          ),
        )
        .toList();

    expect(flux.calls, 1);
    expect(flux.seenKey, 'flux-key');
    expect(flux.seenPrompt, 'a neon poster of a fox');
    expect(events.whereType<ImageGenerated>(), hasLength(1));
  });

  test('a descriptive freeform image prompt (image route) runs live on Flux '
      'when it is the only image key', () async {
    final keys = await _keys({'flux': 'flux-key'});
    final flux = _FakeFlux();
    final service = RealChatService(
      keys: keys,
      fluxClient: flux,
      router: _ForcedRouter(ChatRoute.imageGen),
    );

    const prompt = 'a minimalist navy blue logo for a coffee shop called '
        'Northbound';
    final events = await service
        .sendMessage(
          conversation: _fresh(prompt),
          userInput: prompt,
        )
        .toList();

    expect(flux.calls, 1);
    expect(flux.seenPrompt, prompt);
    expect(events.whereType<ImageGenerated>(), hasLength(1));
  });
}
