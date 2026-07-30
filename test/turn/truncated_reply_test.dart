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

/// How a reply reads when the model runs out of output budget mid-page: the
/// prose intro, the opening fence, part of the document, and then nothing.
/// There is no closing fence, which is what makes extraction impossible and
/// made the old code silently drop the whole thing.
const _cutOff = [
  "Here's a complete, responsive coffee shop website in a single file.\n\n",
  '```html\n',
  '<!DOCTYPE html>\n<html lang="en">\n<head>\n<title>Roast & Co.</title>\n',
  '</head>\n<body>\n<h1>Roast &amp; Co.</h1>\n<p>Single-origin bea',
];

class _ForcedRouter extends ModelRouter {
  @override
  Future<ChatRoute> route({
    required String input,
    String? anthropicKey,
    String? geminiKey,
  }) async =>
      ChatRoute.code;
}

/// Streams [_cutOff] and then ends the way [ending] says.
class _TruncatingClient extends AnthropicClient {
  final ChatEvent ending;
  int seenMaxTokens = 0;

  _TruncatingClient(this.ending);

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
    seenMaxTokens = maxTokens;
    for (final chunk in _cutOff) {
      yield MessageDelta(chunk);
    }
    yield ending;
  }
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

Future<(List<ChatEvent>, _TruncatingClient)> _run(ChatEvent ending) async {
  SharedPreferences.setMockInitialValues({});
  final keys = ApiKeysStore(persistence: PersistenceService());
  await keys.load();
  await keys.setAnthropicKey('test-anthropic-key');
  final client = _TruncatingClient(ending);
  final service = RealChatService(
    keys: keys,
    anthropicClient: client,
    router: _ForcedRouter(),
  );
  const prompt = 'build a local coffee shop website';
  final events = await service
      .sendMessage(conversation: _conversation(prompt), userInput: prompt)
      .toList();
  return (events, client);
}

String _text(List<ChatEvent> events) =>
    events.whereType<MessageDelta>().map((e) => e.chunk).join();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a reply cut off at the output ceiling still shows the page', () async {
    // The reported failure: prose intro, then blank space. Fenced code is
    // withheld while streaming, and only MessageComplete used to release it,
    // so a reply ending in MessageIncomplete dropped the page on the floor.
    final (events, _) = await _run(const MessageIncomplete());

    expect(events.whereType<MessageIncomplete>(), hasLength(1),
        reason: 'the Continue affordance still fires');
    expect(events.whereType<ArtifactCreated>(), isEmpty,
        reason: 'half a document is not a deliverable');

    final text = _text(events);
    expect(text, contains('Roast &amp; Co.'));
    expect(text, contains('<!DOCTYPE html>'));
    expect(text, contains('Single-origin bea'),
        reason: 'right up to where it stopped');
  });

  test('the replayed block is closed, not left open', () async {
    // An open fence renders every following message as code.
    final (events, _) = await _run(const MessageIncomplete());
    final fences = '```'.allMatches(_text(events)).length;
    expect(fences, 2, reason: 'opened once, closed once');
    expect(_text(events).trimRight(), endsWith('```'));
  });

  test('an error mid-page does not lose the page either', () async {
    final (events, _) = await _run(const MessageError('connection reset'));

    expect(events.whereType<MessageError>(), hasLength(1));
    expect(events.whereType<ArtifactCreated>(), isEmpty);
    expect(_text(events), contains('Roast &amp; Co.'));
  });

  test('a code turn asks for the larger output ceiling', () async {
    // The fix that keeps people out of the truncated path at all. Billing is
    // on tokens produced, so this costs nothing on turns that never reach it.
    final (_, client) = await _run(const MessageIncomplete());
    expect(client.seenMaxTokens, AnthropicApiConfig.codeMaxTokens);
    expect(AnthropicApiConfig.codeMaxTokens,
        greaterThan(AnthropicApiConfig.defaultMaxTokens));
  });
}
