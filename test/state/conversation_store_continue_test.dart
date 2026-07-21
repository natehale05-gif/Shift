import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shift_ai/models/attachment.dart';
import 'package:shift_ai/models/chat_message.dart';
import 'package:shift_ai/models/conversation.dart';
import 'package:shift_ai/models/studio_request.dart';
import 'package:shift_ai/services/chat_service.dart';
import 'package:shift_ai/services/persistence_service.dart';
import 'package:shift_ai/state/conversation_store.dart';

/// First reply is cut off (MessageIncomplete); the continuation adds the rest.
class _TruncatingChatService implements ChatService {
  int calls = 0;

  @override
  Stream<ChatEvent> sendMessage({
    required Conversation conversation,
    required String userInput,
    StudioRequest? structuredRequest,
    List<Attachment> attachments = const [],
    ChatOptions options = ChatOptions.none,
  }) async* {
    calls++;
    if (calls == 1) {
      yield const MessageDelta('The first half');
      yield const MessageIncomplete();
    } else {
      yield const MessageDelta(' and the second half.');
      yield const MessageComplete();
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a truncated reply is marked incomplete and Continue appends the rest '
      'to the same message', () async {
    SharedPreferences.setMockInitialValues({});
    final service = _TruncatingChatService();
    final store = ConversationStore(
      chatService: service,
      persistence: PersistenceService(),
    );
    await store.load();
    store.startNewConversation();

    await store.sendMessage('write a long thing');
    final msg = store.current!.messages[1];
    expect(msg.role, MessageRole.assistant);
    expect(msg.status, MessageStatus.incomplete);
    expect(msg.text, 'The first half');

    await store.continueReply(msg.id);

    final done = store.current!.messages[1];
    expect(done.status, MessageStatus.complete);
    expect(done.text, 'The first half and the second half.');
    // Continue streams into the same message — no extra bubble.
    expect(store.current!.messages, hasLength(2));
    expect(service.calls, 2);
  });

  test('continueReply is a no-op on a completed reply', () async {
    SharedPreferences.setMockInitialValues({});
    final service = _TruncatingChatService();
    final store = ConversationStore(
      chatService: service,
      persistence: PersistenceService(),
    );
    await store.load();
    store.startNewConversation();

    await store.sendMessage('one'); // incomplete
    await store.continueReply(store.current!.messages[1].id); // completes it
    final callsAfterComplete = service.calls;

    // Calling again does nothing (message is complete now).
    await store.continueReply(store.current!.messages[1].id);
    expect(service.calls, callsAfterComplete);
  });
}
