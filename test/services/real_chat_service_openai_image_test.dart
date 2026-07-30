import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shift_ai/data/models/chat_message.dart';
import 'package:shift_ai/data/models/conversation.dart';
import 'package:shift_ai/data/persistence/persistence_service.dart';
import 'package:shift_ai/data/stores/api_keys_store.dart';
import 'package:shift_ai/providers/clients/openai_image_client.dart';
import 'package:shift_ai/providers/router/model_router.dart';
import 'package:shift_ai/turn/backends/live_backend.dart';
import 'package:shift_ai/turn/chat_service.dart';

final _png = Uint8List.fromList([137, 80, 78, 71, 9, 9, 9]);

class _ForcedRouter extends ModelRouter {
  @override
  Future<ChatRoute> route({
    required String input,
    String? anthropicKey,
    String? geminiKey,
  }) async =>
      ChatRoute.imageGen;
}

Conversation _conversation(String userInput) => Conversation(
      id: 'c1',
      title: 'x',
      createdAt: DateTime(2026, 7, 30),
      updatedAt: DateTime(2026, 7, 30),
      messages: [
        ChatMessage(
          id: 'u1',
          conversationId: 'c1',
          role: MessageRole.user,
          text: userInput,
          timestamp: DateTime(2026, 7, 30),
        ),
        ChatMessage(
          id: 'a1',
          conversationId: 'c1',
          role: MessageRole.assistant,
          text: '',
          status: MessageStatus.streaming,
          timestamp: DateTime(2026, 7, 30),
        ),
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('an OpenAI-only key generates a real image, not the demo artwork',
      () async {
    // The reported failure: the key was in and tested, and every "generate an
    // image" still came back as the procedural gradient placeholder, because
    // OpenAI did not declare the image capability and the backend fell
    // through to the mock. `callCount` is the assertion that distinguishes
    // "OpenAI drew it" from "it quietly simulated one".
    var callCount = 0;
    final mock = MockClient((request) async {
      callCount++;
      expect(request.url.toString(),
          'https://api.openai.com/v1/images/generations');
      return http.Response(
          jsonEncode({
            'data': [
              {'b64_json': base64Encode(_png)}
            ]
          }),
          200);
    });

    SharedPreferences.setMockInitialValues({});
    final keys = ApiKeysStore(persistence: PersistenceService());
    await keys.load();
    await keys.setKey('openai', 'sk-test');

    final service = RealChatService(
      keys: keys,
      openAiImageClient: OpenAiImageClient(clientFactory: () => mock),
      router: _ForcedRouter(),
    );

    const prompt = 'generate an image of a pink flower';
    final events = await service
        .sendMessage(conversation: _conversation(prompt), userInput: prompt)
        .toList();

    expect(callCount, 1, reason: 'OpenAI actually drew it');
    expect(events.whereType<ImageGenerated>().single.pngBytes, _png);
    expect(events.whereType<StudioResultReady>(), isEmpty,
        reason: 'a simulated image arrives as a studio result card');
  });

  test('with no image-capable key at all it still falls back to the mock',
      () async {
    SharedPreferences.setMockInitialValues({});
    final keys = ApiKeysStore(persistence: PersistenceService());
    await keys.load();

    final service = RealChatService(keys: keys, router: _ForcedRouter());

    const prompt = 'generate an image of a pink flower';
    final events = await service
        .sendMessage(conversation: _conversation(prompt), userInput: prompt)
        .toList();

    // Demo mode still answers; it just is not reached when a key exists.
    expect(events, isNotEmpty);
  });
}
