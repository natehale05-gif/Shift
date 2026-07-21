import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shift_ai/models/artifact.dart';
import 'package:shift_ai/models/message_block.dart';
import 'package:shift_ai/services/mock_chat_service.dart';
import 'package:shift_ai/services/persistence_service.dart';
import 'package:shift_ai/state/conversation_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('an interactive artifact yields an inline (interactive) ref block and '
      'does not auto-open the side panel', () async {
    SharedPreferences.setMockInitialValues({});
    var opened = 0;
    final store = ConversationStore(
      chatService: MockChatService(),
      persistence: PersistenceService(),
    )..onArtifactCreated = (_) => opened++;
    await store.load();
    store.startNewConversation();

    await store.sendMessage('make a recipe card for banana bread');

    final assistant = store.current!.messages.last;
    final refs = assistant.blocks.whereType<ArtifactRefBlock>().toList();
    expect(refs, hasLength(1));
    expect(refs.single.interactive, isTrue,
        reason: 'recipe cards render inline, not as a panel card');

    // The conversation's artifact is flagged interactive too.
    final artifact = store.current!.artifacts.single;
    expect(artifact.interactive, isTrue);
    expect(artifact.kind, ArtifactKind.html);

    // Interactive results render inline, so the panel is never auto-opened.
    expect(opened, 0);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
