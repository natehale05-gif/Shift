import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shift_ai/data/models/attachment.dart';
import 'package:shift_ai/data/models/chat_message.dart';
import 'package:shift_ai/data/models/conversation.dart';
import 'package:shift_ai/data/models/studio_request.dart';
import 'package:shift_ai/turn/chat_service.dart';
import 'package:shift_ai/data/persistence/persistence_service.dart';
import 'package:shift_ai/data/stores/conversation_store.dart';

/// A service whose reply stream is driven by hand, so a test can observe the
/// mid-stream (streaming) state and then interrupt it.
class _ManualChatService implements ChatService {
  final controller = StreamController<ChatEvent>();

  @override
  Stream<ChatEvent> sendMessage({
    required Conversation conversation,
    required String userInput,
    StudioRequest? structuredRequest,
    List<Attachment> attachments = const [],
    ChatOptions options = ChatOptions.none,
  }) =>
      controller.stream;
}

Future<void> _tick() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('stopGeneration interrupts a streaming reply and keeps the partial '
      'text as a completed message', () async {
    SharedPreferences.setMockInitialValues({});
    final service = _ManualChatService();
    final store = ConversationStore(
      chatService: service,
      persistence: PersistenceService(),
    );
    await store.load();
    store.startNewConversation();

    // Fire and forget — the returned future completes only when the stream
    // ends, which it never does here (we interrupt instead).
    unawaited(store.sendMessage('write me a long essay'));
    await _tick();

    service.controller.add(const MessageDelta('Once upon a time'));
    await _tick();

    expect(store.isStreaming, isTrue);
    final streaming = store.current!.messages.last;
    expect(streaming.role, MessageRole.assistant);
    expect(streaming.status, MessageStatus.streaming);
    expect(streaming.text, contains('Once upon a time'));

    store.stopGeneration();
    await _tick();

    expect(store.isStreaming, isFalse);
    final stopped = store.current!.messages.last;
    expect(stopped.status, MessageStatus.complete);
    expect(stopped.text, contains('Once upon a time'),
        reason: 'the partial reply is preserved, like Claude\'s stop');

    // Events arriving after a stop are ignored (subscription cancelled).
    service.controller.add(const MessageDelta(' — ignored'));
    await _tick();
    expect(store.current!.messages.last.text, isNot(contains('ignored')));

    await service.controller.close();
  });

  test('isStreaming is scoped to the current conversation', () async {
    SharedPreferences.setMockInitialValues({});
    final service = _ManualChatService();
    final store = ConversationStore(
      chatService: service,
      persistence: PersistenceService(),
    );
    await store.load();
    store.startNewConversation();
    final streamingConvo = store.current!.id;

    unawaited(store.sendMessage('hello'));
    await _tick();
    service.controller.add(const MessageDelta('hi'));
    await _tick();
    expect(store.isStreaming, isTrue);

    // Switch to a different conversation: the composer there shows Send.
    store.startNewConversation();
    expect(store.current!.id, isNot(streamingConvo));
    expect(store.isStreaming, isFalse);

    store.stopGeneration();
    await service.controller.close();
  });
}
