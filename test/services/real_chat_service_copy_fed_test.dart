import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shift_ai/data/models/chat_message.dart';
import 'package:shift_ai/data/models/conversation.dart';
import 'package:shift_ai/data/models/studio_result.dart';
import 'package:shift_ai/data/models/studio_type.dart';
import 'package:shift_ai/services/chat_service.dart';
import 'package:shift_ai/data/persistence/persistence_service.dart';
import 'package:shift_ai/services/providers/anthropic_client.dart';
import 'package:shift_ai/services/real_chat_service.dart';
import 'package:shift_ai/data/stores/api_keys_store.dart';

/// Records the completion prompt and returns a canned "written" script, so we
/// can prove Copy & Scripts' live output is what the media result carries.
class _ScriptWritingAnthropic extends AnthropicClient {
  String? lastPrompt;

  @override
  Future<String> complete({
    required String apiKey,
    required String model,
    required String prompt,
    String? systemPrompt,
    int maxTokens = 200,
  }) async {
    lastPrompt = prompt;
    return 'Welcome aboard — your journey starts right here, right now.';
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

Future<ApiKeysStore> _anthropicKeys() async {
  SharedPreferences.setMockInitialValues({});
  final keys = ApiKeysStore(persistence: PersistenceService());
  await keys.load();
  await keys.setAnthropicKey('test-anthropic-key');
  return keys;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a live write-and-narrate uses Claude for the script and carries it '
      'as the voice transcript', () async {
    final keys = await _anthropicKeys();
    final anthropic = _ScriptWritingAnthropic();
    final service = RealChatService(keys: keys, anthropicClient: anthropic);

    final events = await service
        .sendMessage(
          conversation: _fresh('write and narrate a welcome message'),
          userInput: 'write and narrate a welcome message',
        )
        .toList();

    // Claude was asked to write a voiceover script.
    expect(anthropic.lastPrompt, contains('voiceover script'));

    expect(events.whereType<RoutingDetected>().single.studioType,
        StudioType.voiceAvatarStudio);
    final result = events.whereType<StudioResultReady>().single.result;
    expect(result, isA<AudioResult>());
    expect((result as AudioResult).transcript,
        'Welcome aboard — your journey starts right here, right now.');
    expect(events.last, isA<MessageComplete>());
  });

  test('a live write-a-jingle produces a music result from Claude\'s hook',
      () async {
    final keys = await _anthropicKeys();
    final service =
        RealChatService(keys: keys, anthropicClient: _ScriptWritingAnthropic());

    final events = await service
        .sendMessage(
          conversation: _fresh('write a jingle for my coffee brand'),
          userInput: 'write a jingle for my coffee brand',
        )
        .toList();

    expect(events.whereType<RoutingDetected>().single.studioType,
        StudioType.musicStudio);
    expect(events.whereType<StudioResultReady>().single.result,
        isA<AudioResult>());
  });
}
