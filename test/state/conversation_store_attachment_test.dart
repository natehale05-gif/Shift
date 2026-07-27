import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shift_ai/data/models/attachment.dart';
import 'package:shift_ai/data/models/conversation.dart';
import 'package:shift_ai/data/models/studio_request.dart';
import 'package:shift_ai/services/chat_service.dart';
import 'package:shift_ai/data/persistence/persistence_service.dart';
import 'package:shift_ai/data/stores/conversation_store.dart';

class _EchoService implements ChatService {
  @override
  Stream<ChatEvent> sendMessage({
    required Conversation conversation,
    required String userInput,
    StudioRequest? structuredRequest,
    List<Attachment> attachments = const [],
    ChatOptions options = ChatOptions.none,
  }) async* {
    yield const MessageDelta('ok');
    yield const MessageComplete();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('attachment bytes are persisted to the asset store on send', () async {
    SharedPreferences.setMockInitialValues({});
    final persistence = PersistenceService();
    final store = ConversationStore(
      chatService: _EchoService(),
      persistence: persistence,
    );
    await store.load();
    store.startNewConversation();

    final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
    await store.sendMessage(
      'here is a file',
      attachments: [
        Attachment(
          id: 'a1',
          name: 'note.txt',
          mimeType: 'text/plain',
          kind: AttachmentKind.text,
          bytes: bytes,
        ),
      ],
    );

    final userMessage = store.current!.messages.first;
    final attachment = userMessage.attachments.single;
    // The attachment now carries an assetId and its bytes are retrievable.
    expect(attachment.assetId, isNotNull);
    final stored = await persistence.loadAsset(attachment.assetId!);
    expect(stored, bytes);

    // toJson drops raw bytes but keeps the assetId so it survives reload.
    expect(attachment.toJson().containsKey('bytes'), isFalse);
    expect(attachment.toJson()['assetId'], attachment.assetId);
  });
}
