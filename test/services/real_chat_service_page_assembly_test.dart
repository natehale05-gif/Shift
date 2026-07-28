import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shift_ai/data/models/artifact.dart';
import 'package:shift_ai/data/models/attachment.dart';
import 'package:shift_ai/data/models/chat_message.dart';
import 'package:shift_ai/data/models/conversation.dart';
import 'package:shift_ai/services/chat_service.dart';
import 'package:shift_ai/data/persistence/persistence_service.dart';
import 'package:shift_ai/providers/clients/anthropic_client.dart';
import 'package:shift_ai/services/real_chat_service.dart';
import 'package:shift_ai/providers/router/model_router.dart';
import 'package:shift_ai/data/stores/api_keys_store.dart';

const _pageHtml = '<!DOCTYPE html>\n'
    '<html>\n'
    '<body>\n'
    '<h1>Northbound</h1>\n'
    '<p>Claude wrote this copy.</p>\n'
    '</body>\n'
    '</html>';

class _ForcedRouter extends ModelRouter {
  @override
  Future<ChatRoute> route({
    required String input,
    String? anthropicKey,
    String? geminiKey,
  }) async =>
      ChatRoute.code;
}

class _FakeAnthropicClient extends AnthropicClient {
  @override
  Stream<ChatEvent> streamChat({
    required String apiKey,
    required Conversation conversation,
    required String userInput,
    required String model,
    List<Attachment> attachments = const [],
    String? systemPrompt,
    List<Map<String, dynamic>> tools = const [],
    bool extendedThinking = true,
    int maxContinuations = 5,
  }) async* {
    yield const MessageDelta('Here you go:\n\n```html\n$_pageHtml\n```');
    yield const MessageComplete();
  }
}

Conversation _fresh(String userInput) => Conversation(
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

Future<ApiKeysStore> _anthropicOnlyKeys() async {
  SharedPreferences.setMockInitialValues({});
  final keys = ApiKeysStore(persistence: PersistenceService());
  await keys.load();
  await keys.setAnthropicKey('test-anthropic-key');
  return keys;
}

Future<Artifact> _run(String prompt) async {
  final keys = await _anthropicOnlyKeys();
  final service = RealChatService(
    keys: keys,
    anthropicClient: _FakeAnthropicClient(),
    router: _ForcedRouter(),
  );
  final events =
      await service.sendMessage(conversation: _fresh(prompt), userInput: prompt).toList();
  return events.whereType<ArtifactCreated>().single.artifact;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a website + soundtrack embeds a synthesized audio player into the '
      'page Claude built', () async {
    final artifact =
        await _run('build me a bakery website with a soundtrack');
    expect(artifact.latest.content, contains('<audio controls'));
    expect(artifact.latest.content, contains('Soundtrack'));
    // Claude's own copy is preserved (copy is not re-embedded in live mode).
    expect(artifact.latest.content, contains('Claude wrote this copy.'));
  });

  test('a website + video clip embeds a simulated-video block', () async {
    final artifact =
        await _run('build me a bakery website with a video clip');
    expect(artifact.latest.content, contains('Simulated video'));
  });

  test('a website + photos + soundtrack embeds both, no Gemini key -> '
      'procedural photos', () async {
    final artifact = await _run(
        'build me a dog treat website with several photos and a soundtrack');
    expect('<img'.allMatches(artifact.latest.content).length, 3);
    expect(artifact.latest.content, contains('<audio controls'));
  });

  test('a plain page has no embedded media', () async {
    final artifact = await _run('build me a landing page for my bakery');
    expect(artifact.latest.content.contains('<img'), isFalse);
    expect(artifact.latest.content.contains('<audio'), isFalse);
  });
}
