import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shift_ai/data/models/artifact.dart';
import 'package:shift_ai/data/models/chat_message.dart';
import 'package:shift_ai/data/models/conversation.dart';
import 'package:shift_ai/turn/chat_service.dart';
import 'package:shift_ai/providers/clients/provider_access.dart';
import 'package:shift_ai/data/persistence/persistence_service.dart';
import 'package:shift_ai/providers/clients/gemini_client.dart';
import 'package:shift_ai/turn/backends/live_backend.dart';
import 'package:shift_ai/providers/router/model_router.dart';
import 'package:shift_ai/data/stores/api_keys_store.dart';

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
    required ProviderAccess access,
    required String prompt,
  }) async* {
    lastImagePrompt = prompt;
    yield ImageGenerated(pngBytes: Uint8List.fromList([1, 2, 3]), alt: 'test');
    yield const MessageComplete();
  }
}

Conversation _withHtmlArtifact(String userInput) => Conversation(
      id: 'c1',
      title: 'x',
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

Future<ApiKeysStore> _liveGeminiKeys() async {
  SharedPreferences.setMockInitialValues({});
  final keys = ApiKeysStore(persistence: PersistenceService());
  await keys.load();
  await keys.setGeminiKey('test-gemini-key');
  return keys;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('adding a hero image to an existing artifact calls Gemini and '
      'splices the bytes into the artifact instead of showing them inline',
      () async {
    final keys = await _liveGeminiKeys();
    final gemini = _RecordingGeminiClient();
    final service = RealChatService(
      keys: keys,
      geminiClient: gemini,
      router: _ForcedRouter(ChatRoute.imageGen),
    );

    const prompt = 'add a hero image to the website';
    final events = await service
        .sendMessage(
          conversation: _withHtmlArtifact(prompt),
          userInput: prompt,
        )
        .toList();

    expect(gemini.lastImagePrompt, prompt);
    expect(events.whereType<ImageGenerated>(), isEmpty,
        reason: 'the image is embedded, not shown as its own inline block');

    final updated = events.whereType<ArtifactUpdated>().single.artifact;
    expect(updated.id, 'art1');
    expect(updated.versions, hasLength(2));
    expect(updated.latest.content, contains('<img'));
    expect(events.last, isA<MessageComplete>());
  });

  test('a standalone image request with no site reference generates '
      'normally even when an artifact exists', () async {
    final keys = await _liveGeminiKeys();
    final gemini = _RecordingGeminiClient();
    final service = RealChatService(
      keys: keys,
      geminiClient: gemini,
      router: _ForcedRouter(ChatRoute.imageGen),
    );

    const prompt = 'make me a completely separate poster for a concert';
    final events = await service
        .sendMessage(
          conversation: _withHtmlArtifact(prompt),
          userInput: prompt,
        )
        .toList();

    expect(gemini.lastImagePrompt, prompt);
    expect(events.whereType<ImageGenerated>(), hasLength(1));
    expect(events.whereType<ArtifactUpdated>(), isEmpty);
  });

  test('a live user adding background music to the site embeds an audio '
      'player into the artifact (synthesized via the mock)', () async {
    final keys = await _liveGeminiKeys();
    final service = RealChatService(keys: keys, geminiClient: _RecordingGeminiClient());

    const prompt = 'add background music to the website';
    final events = await service
        .sendMessage(conversation: _withHtmlArtifact(prompt), userInput: prompt)
        .toList();

    final updated = events.whereType<ArtifactUpdated>().single.artifact;
    expect(updated.id, 'art1');
    expect(updated.latest.content, contains('<audio controls'));
    expect(events.whereType<StudioResultReady>(), isEmpty);
  });

  test('a live user adding a video to the site embeds a video block into the '
      'artifact', () async {
    final keys = await _liveGeminiKeys();
    final service = RealChatService(keys: keys, geminiClient: _RecordingGeminiClient());

    const prompt = 'add a video to the website';
    final events = await service
        .sendMessage(conversation: _withHtmlArtifact(prompt), userInput: prompt)
        .toList();

    final updated = events.whereType<ArtifactUpdated>().single.artifact;
    expect(updated.latest.content, contains('Simulated video'));
    expect(events.whereType<StudioResultReady>(), isEmpty);
  });
}
