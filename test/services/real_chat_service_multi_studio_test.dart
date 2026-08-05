import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shift_ai/providers/clients/provider_access.dart';
import 'package:shift_ai/data/models/artifact.dart';
import 'package:shift_ai/data/models/attachment.dart';
import 'package:shift_ai/data/models/chat_message.dart';
import 'package:shift_ai/data/models/conversation.dart';
import 'package:shift_ai/data/models/studio_type.dart';
import 'package:shift_ai/turn/chat_service.dart';
import 'package:shift_ai/data/persistence/persistence_service.dart';
import 'package:shift_ai/providers/clients/anthropic_api_config.dart';
import 'package:shift_ai/providers/clients/anthropic_client.dart';
import 'package:shift_ai/providers/clients/gemini_client.dart';
import 'package:shift_ai/turn/backends/live_backend.dart';
import 'package:shift_ai/providers/router/model_router.dart';
import 'package:shift_ai/data/stores/api_keys_store.dart';

// extractCodeArtifact only treats a fenced block as artifact-worthy once
// it's at least 5 lines — mirror that shape here.
const _pageHtml = '<!DOCTYPE html>\n'
    '<html>\n'
    '<body>\n'
    '<h1>Northbound Treats</h1>\n'
    '</body>\n'
    '</html>';

/// Always returns [forced] — proves the wants-both-studios override forces
/// Code Studio directly, without depending on (or being derailed by) this
/// router.
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

class _FakeAnthropicClient extends AnthropicClient {
  @override
  Stream<ChatEvent> streamChat({
    required ProviderAccess access,
    required Conversation conversation,
    required String userInput,
    required String model,
    List<Attachment> attachments = const [],
    String? systemPrompt,
    List<Map<String, dynamic>> tools = const [],
    bool extendedThinking = true,
    int maxContinuations = 5,
    int maxTokens = AnthropicApiConfig.defaultMaxTokens,
  }) async* {
    yield const MessageDelta(
        'Here\'s the page:\n\n```html\n$_pageHtml\n```');
    yield const MessageComplete();
  }
}

class _CountingGeminiClient extends GeminiClient {
  int callCount = 0;

  @override
  Stream<ChatEvent> generateImage({
    required ProviderAccess access,
    required String prompt,
  }) async* {
    callCount++;
    yield ImageGenerated(
      pngBytes: Uint8List.fromList([callCount]),
      alt: 'test',
    );
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

Future<ApiKeysStore> _keys({required bool gemini}) async {
  SharedPreferences.setMockInitialValues({});
  final keys = ApiKeysStore(persistence: PersistenceService());
  await keys.load();
  await keys.setAnthropicKey('test-anthropic-key');
  if (gemini) await keys.setGeminiKey('test-gemini-key');
  return keys;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a fresh "website with photos" request forces Code Studio and '
      'embeds real Gemini images into the artifact Claude built',
      () async {
    final keys = await _keys(gemini: true);
    final gemini = _CountingGeminiClient();
    // Deliberately wrong: proves the wants-both override wins, not this
    // router.
    final service = RealChatService(
      keys: keys,
      anthropicClient: _FakeAnthropicClient(),
      geminiClient: gemini,
      router: _ForcedRouter(ChatRoute.chat),
    );

    const prompt = 'build me a dog treat website with several photos';
    final events = await service
        .sendMessage(
          conversation: _freshConversation(prompt),
          userInput: prompt,
        )
        .toList();

    expect(events.whereType<RoutingDetected>().single.studioType,
        StudioType.codeStudio);
    final artifact = events.whereType<ArtifactCreated>().single.artifact;
    expect(artifact.kind, ArtifactKind.html);
    expect('<img'.allMatches(artifact.latest.content).length, 3);
    expect(gemini.callCount, 3);
  });

  test('with no Gemini key, the same request still gets a fully composed '
      'artifact via procedural fallback images', () async {
    final keys = await _keys(gemini: false);
    final gemini = _CountingGeminiClient();
    final service = RealChatService(
      keys: keys,
      anthropicClient: _FakeAnthropicClient(),
      geminiClient: gemini,
      router: _ForcedRouter(ChatRoute.code),
    );

    const prompt = 'build me a dog treat website with several photos';
    final events = await service
        .sendMessage(
          conversation: _freshConversation(prompt),
          userInput: prompt,
        )
        .toList();

    final artifact = events.whereType<ArtifactCreated>().single.artifact;
    expect('<img'.allMatches(artifact.latest.content).length, 3);
    expect(gemini.callCount, 0);
  });

  test('a plain page request with no image keyword is unaffected', () async {
    final keys = await _keys(gemini: true);
    final gemini = _CountingGeminiClient();
    final service = RealChatService(
      keys: keys,
      anthropicClient: _FakeAnthropicClient(),
      geminiClient: gemini,
      router: _ForcedRouter(ChatRoute.code),
    );

    const prompt = 'build me a landing page for my bakery';
    final events = await service
        .sendMessage(
          conversation: _freshConversation(prompt),
          userInput: prompt,
        )
        .toList();

    final artifact = events.whereType<ArtifactCreated>().single.artifact;
    expect(artifact.latest.content.contains('<img'), isFalse);
    expect(gemini.callCount, 0);
  });
}
