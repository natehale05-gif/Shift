import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shift_ai/models/attachment.dart';
import 'package:shift_ai/models/chat_message.dart';
import 'package:shift_ai/models/conversation.dart';
import 'package:shift_ai/models/studio_request.dart';
import 'package:shift_ai/services/chat_service.dart';
import 'package:shift_ai/services/persistence_service.dart';
import 'package:shift_ai/state/conversation_store.dart';

/// Deterministic scripted service: replies instantly with a single text
/// chunk that echoes the input, so store behavior is testable without the
/// mock's random delays.
class _EchoChatService implements ChatService {
  final List<String> inputs = [];
  final List<ChatOptions> options = [];

  @override
  Stream<ChatEvent> sendMessage({
    required Conversation conversation,
    required String userInput,
    StudioRequest? structuredRequest,
    List<Attachment> attachments = const [],
    ChatOptions options = ChatOptions.none,
  }) async* {
    inputs.add(userInput);
    this.options.add(options);
    yield MessageDelta('echo: $userInput');
    yield const MessageComplete();
  }
}

Future<(ConversationStore, _EchoChatService)> _makeStore() async {
  SharedPreferences.setMockInitialValues({});
  final service = _EchoChatService();
  final store = ConversationStore(
    chatService: service,
    persistence: PersistenceService(),
  );
  await store.load();
  return (store, service);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('rename, star, and project assignment persist on the conversation',
      () async {
    final (store, _) = await _makeStore();
    store.startNewConversation();
    final id = store.current!.id;

    store.renameConversation(id, 'Bakery plans');
    store.toggleStar(id);
    store.setConversationProject(id, 'p1');

    expect(store.current!.title, 'Bakery plans');
    expect(store.current!.starred, isTrue);
    expect(store.current!.projectId, 'p1');

    store.toggleStar(id);
    expect(store.current!.starred, isFalse);
  });

  test('search matches titles and message text case-insensitively',
      () async {
    final (store, _) = await _makeStore();
    store.startNewConversation();
    await store.sendMessage('tell me about croissants');
    store.startNewConversation();
    await store.sendMessage('quarterly revenue forecast');

    expect(store.search('CROISSANT'), hasLength(1));
    expect(store.search('echo: quarterly'), hasLength(1));
    expect(store.search('nonexistent-term'), isEmpty);
    expect(store.search(''), hasLength(2));
  });

  test('editAndResend truncates from the edited message and replays',
      () async {
    final (store, service) = await _makeStore();
    store.startNewConversation();
    await store.sendMessage('first question');
    await store.sendMessage('second question');
    expect(store.current!.messages, hasLength(4));

    final secondUserMessage = store.current!.messages[2];
    expect(secondUserMessage.role, MessageRole.user);
    await store.editAndResend(secondUserMessage.id, 'revised question');

    final messages = store.current!.messages;
    expect(messages, hasLength(4));
    expect(messages[2].text, 'revised question');
    expect(messages[3].text, 'echo: revised question');
    expect(service.inputs.last, 'revised question');
  });

  test('regenerate keeps the old reply as a switchable variant', () async {
    final (store, service) = await _makeStore();
    store.startNewConversation();
    await store.sendMessage('tell me a joke');
    final assistantMessage = store.current!.messages[1];
    expect(assistantMessage.role, MessageRole.assistant);

    await store.regenerate(assistantMessage.id);

    // Same two messages, no new pair — the reply is regenerated in place.
    expect(store.current!.messages, hasLength(2));
    expect(service.inputs, ['tell me a joke', 'tell me a joke']);

    final regenerated = store.current!.messages[1];
    expect(regenerated.hasVariants, isTrue);
    expect(regenerated.variantCount, 2);
    // The live (newest) response is shown by default.
    expect(regenerated.activeVariant, 1);
    expect(regenerated.displayText, 'echo: tell me a joke');

    // Stepping back shows the archived first response.
    store.selectVariant(regenerated.id, 0);
    expect(store.current!.messages[1].activeVariant, 0);
    expect(store.current!.messages[1].displayText, 'echo: tell me a joke');
  });

  test('setFeedback toggles thumbs up/down on an assistant reply', () async {
    final (store, _) = await _makeStore();
    store.startNewConversation();
    await store.sendMessage('hello there');
    final id = store.current!.messages[1].id;

    store.setFeedback(id, MessageFeedback.up);
    expect(store.current!.messages[1].feedback, MessageFeedback.up);

    // Same thumb again clears it; the opposite thumb switches.
    store.setFeedback(id, MessageFeedback.up);
    expect(store.current!.messages[1].feedback, MessageFeedback.none);
    store.setFeedback(id, MessageFeedback.down);
    expect(store.current!.messages[1].feedback, MessageFeedback.down);
  });

  test('sendMessage forwards the assembled system prompt in options',
      () async {
    final (store, service) = await _makeStore();
    store.startNewConversation();
    await store.sendMessage(
      'hello',
      options: const ChatOptions(systemPrompt: 'You are SHIFT AI. TEST.'),
    );
    expect(service.options.single.systemPrompt, contains('TEST'));
  });
}
