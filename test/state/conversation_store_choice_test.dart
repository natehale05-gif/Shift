import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shift_ai/data/models/message_block.dart';
import 'package:shift_ai/data/persistence/persistence_service.dart';
import 'package:shift_ai/data/stores/conversation_store.dart';
import 'package:shift_ai/turn/backends/mock_backend.dart';

Future<ConversationStore> _store() async {
  SharedPreferences.setMockInitialValues({});
  final store = ConversationStore(
    chatService: MockChatService(),
    persistence: PersistenceService(),
  );
  await store.load();
  store.startNewConversation();
  return store;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a terse studio prompt offers tappable options alongside the question',
      () async {
    final store = await _store();
    await store.sendMessage('make me a logo');

    final choice = store.current!.messages.last.blocks
        .whereType<ChoiceBlock>()
        .single;
    expect(choice.options, isNotEmpty);
    expect(choice.answered, isFalse,
        reason: 'a freshly offered question has no answer yet');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('answering stamps the block and sends exactly one message', () async {
    final store = await _store();
    await store.sendMessage('make me a logo');

    final assistant = store.current!.messages.last;
    final choice = assistant.blocks.whereType<ChoiceBlock>().single;
    final before = store.current!.messages.length;

    await store.answerChoice(
      messageId: assistant.id,
      blockId: choice.id,
      chosen: ['Bold'],
    );

    // The question stays on screen, now showing what was picked.
    final answered = store.current!.messages
        .firstWhere((m) => m.id == assistant.id)
        .blocks
        .whereType<ChoiceBlock>()
        .single;
    expect(answered.chosen, ['Bold']);
    expect(answered.answered, isTrue);

    // One user turn and one assistant reply — the selection goes through the
    // same path as anything the user types, so nothing is sent twice.
    expect(store.current!.messages.length, before + 2);
    expect(store.current!.messages[before].text, 'Bold');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('an empty selection sends nothing', () async {
    final store = await _store();
    await store.sendMessage('make me a logo');

    final assistant = store.current!.messages.last;
    final choice = assistant.blocks.whereType<ChoiceBlock>().single;
    final before = store.current!.messages.length;

    await store.answerChoice(
      messageId: assistant.id,
      blockId: choice.id,
      chosen: const [],
    );

    expect(store.current!.messages.length, before);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a multi-select answer is sent as one message', () async {
    final store = await _store();
    await store.sendMessage('make me a logo');

    final assistant = store.current!.messages.last;
    final choice = assistant.blocks.whereType<ChoiceBlock>().single;
    final before = store.current!.messages.length;

    await store.answerChoice(
      messageId: assistant.id,
      blockId: choice.id,
      chosen: ['Bold', 'Minimal'],
    );

    expect(store.current!.messages.length, before + 2);
    expect(store.current!.messages[before].text, 'Bold, Minimal');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
