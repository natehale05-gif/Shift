import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shift_ai/data/models/attachment.dart';
import 'package:shift_ai/data/models/chat_message.dart';
import 'package:shift_ai/data/models/conversation.dart';
import 'package:shift_ai/data/persistence/persistence_service.dart';
import 'package:shift_ai/data/stores/api_keys_store.dart';
import 'package:shift_ai/providers/clients/anthropic_api_config.dart';
import 'package:shift_ai/providers/clients/anthropic_client.dart';
import 'package:shift_ai/providers/router/model_router.dart';
import 'package:shift_ai/turn/backends/live_backend.dart';
import 'package:shift_ai/turn/chat_service.dart';
import 'package:shift_ai/turn/choice_parsing.dart';

class _ChatRouter extends ModelRouter {
  @override
  Future<ChatRoute> route({
    required String input,
    String? anthropicKey,
    String? geminiKey,
  }) async =>
      ChatRoute.chat;
}

/// Replies with whatever [reply] holds, in one delta.
class _FakeAnthropicClient extends AnthropicClient {
  final String reply;
  _FakeAnthropicClient(this.reply);

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
    int maxTokens = AnthropicApiConfig.defaultMaxTokens,
  }) async* {
    yield MessageDelta(reply);
    yield const MessageComplete();
  }
}

Conversation _conversation(String userInput) => Conversation(
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
      ],
    );

Future<List<ChatEvent>> _run(String reply) async {
  SharedPreferences.setMockInitialValues({});
  final keys = ApiKeysStore(persistence: PersistenceService());
  await keys.load();
  await keys.setAnthropicKey('test-anthropic-key');
  final service = RealChatService(
    keys: keys,
    anthropicClient: _FakeAnthropicClient(reply),
    router: _ChatRouter(),
  );
  return service
      .sendMessage(
        conversation: _conversation('write me a caption'),
        userInput: 'write me a caption',
      )
      .toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a shift:choices fence becomes a question, not JSON in the reply',
      () async {
    final events = await _run('Which platform is this for?\n\n'
        '```$choiceFenceTag\n'
        '{"question": "Pick one", "options": ["TikTok", "LinkedIn"]}\n'
        '```\n');

    final offered = events.whereType<ChoiceOffered>().single;
    expect(offered.question, 'Pick one');
    expect(offered.options, ['TikTok', 'LinkedIn']);
    expect(offered.id, isNotEmpty);

    // The JSON must not also arrive as text — the whole point of withholding
    // the fence is that the user sees buttons instead of a payload.
    final text = events.whereType<MessageDelta>().map((e) => e.chunk).join();
    expect(text, contains('Which platform is this for?'));
    expect(text, isNot(contains('"options"')));
    expect(text, isNot(contains(choiceFenceTag)));
  });

  test('a malformed choice block is replayed as text rather than swallowed',
      () async {
    // Withholding is a presentation choice. A block that produced no question
    // has to come back, or the reply loses content.
    final events = await _run('Here you go:\n\n'
        '```$choiceFenceTag\n'
        '{"question": "Pick one", "options": ["Only one"]}\n'
        '```\n');

    expect(events.whereType<ChoiceOffered>(), isEmpty);
    final text = events.whereType<MessageDelta>().map((e) => e.chunk).join();
    expect(text, contains('Only one'));
  });

  test('an ordinary reply offers no choices', () async {
    final events = await _run('The capital of France is Paris.');

    expect(events.whereType<ChoiceOffered>(), isEmpty);
    final text = events.whereType<MessageDelta>().map((e) => e.chunk).join();
    expect(text, contains('Paris'));
  });
}
