import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shift_ai/providers/clients/provider_access.dart';
import 'package:shift_ai/data/models/artifact.dart';
import 'package:shift_ai/data/models/attachment.dart';
import 'package:shift_ai/data/models/chat_message.dart';
import 'package:shift_ai/data/models/conversation.dart';
import 'package:shift_ai/turn/chat_service.dart';
import 'package:shift_ai/data/persistence/persistence_service.dart';
import 'package:shift_ai/providers/clients/anthropic_api_config.dart';
import 'package:shift_ai/providers/clients/anthropic_client.dart';
import 'package:shift_ai/turn/backends/live_backend.dart';
import 'package:shift_ai/providers/router/model_router.dart';
import 'package:shift_ai/data/stores/api_keys_store.dart';

const _revisedHtml = '<!DOCTYPE html>\n'
    '<html>\n'
    '<body>\n'
    '<h1>Northbound</h1>\n'
    '<button style="background:red">Buy</button>\n'
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
    yield const MessageDelta('Updated:\n\n```html\n$_revisedHtml\n```');
    yield const MessageComplete();
  }
}

Artifact _existingPage() => Artifact(
      id: 'a1',
      conversationId: 'c1',
      title: 'Northbound landing page',
      kind: ArtifactKind.html,
      versions: [
        ArtifactVersion(
          content: '<html><body><h1>Northbound</h1></body></html>',
          createdAt: DateTime(2026, 7, 20),
        ),
      ],
    );

Conversation _conversation(String userInput, List<Artifact> artifacts) =>
    Conversation(
      id: 'c1',
      title: 'x',
      createdAt: DateTime(2026, 7, 20),
      updatedAt: DateTime(2026, 7, 20),
      artifacts: artifacts,
      messages: [
        ChatMessage(
          id: 'u1',
          conversationId: 'c1',
          role: MessageRole.user,
          text: userInput,
          timestamp: DateTime(2026, 7, 20),
        ),
        ChatMessage(
          id: 'a1m',
          conversationId: 'c1',
          role: MessageRole.assistant,
          text: '',
          status: MessageStatus.streaming,
          timestamp: DateTime(2026, 7, 20),
        ),
      ],
    );

Future<List<ChatEvent>> _run(String prompt, List<Artifact> artifacts) async {
  SharedPreferences.setMockInitialValues({});
  final keys = ApiKeysStore(persistence: PersistenceService());
  await keys.load();
  await keys.setAnthropicKey('test-anthropic-key');
  final service = RealChatService(
    keys: keys,
    anthropicClient: _FakeAnthropicClient(),
    router: _ForcedRouter(),
  );
  return service
      .sendMessage(
        conversation: _conversation(prompt, artifacts),
        userInput: prompt,
      )
      .toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a revision becomes a new version of the existing artifact', () async {
    // Live mode used to always create, so asking for a change produced a
    // second near-identical artifact instead of a v2 the panel can step back
    // through. Demo mode revised — the two disagreed on the same prompt.
    final events =
        await _run('change the code so the button is red', [_existingPage()]);

    expect(events.whereType<ArtifactCreated>(), isEmpty);
    final updated = events.whereType<ArtifactUpdated>().single;
    expect(updated.artifact.id, 'a1');
    expect(updated.artifact.versions, hasLength(2));
    expect(updated.artifact.latest.content, contains('background:red'));
  });

  test('a new build still creates a separate artifact', () async {
    final events =
        await _run('build me a landing page for a law firm', [_existingPage()]);

    expect(events.whereType<ArtifactUpdated>(), isEmpty);
    expect(events.whereType<ArtifactCreated>().single.artifact.id, isNot('a1'));
  });

  test('with no existing artifact a code turn creates one', () async {
    final events = await _run('write me a landing page', const []);

    expect(events.whereType<ArtifactUpdated>(), isEmpty);
    expect(events.whereType<ArtifactCreated>(), hasLength(1));
  });
}
