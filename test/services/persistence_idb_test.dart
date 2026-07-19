import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shift_ai/models/chat_message.dart';
import 'package:shift_ai/models/conversation.dart';
import 'package:shift_ai/services/persistence_service.dart';

Conversation _conversation(String id, {DateTime? updatedAt}) => Conversation(
      id: id,
      title: 'Chat $id',
      createdAt: DateTime(2026, 7, 19, 9),
      updatedAt: updatedAt ?? DateTime(2026, 7, 19, 10),
      messages: [
        ChatMessage(
          id: 'm-$id',
          conversationId: id,
          role: MessageRole.user,
          text: 'hello from $id',
          timestamp: DateTime(2026, 7, 19, 9, 30),
        ),
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('migrates the old localStorage blob into IndexedDB once', () async {
    final oldBlob = jsonEncode([
      _conversation('legacy1').toJson(),
      _conversation('legacy2').toJson(),
    ]);
    SharedPreferences.setMockInitialValues({
      'shift_ai.conversations.v1': oldBlob,
      'shift_ai.theme_mode.v1': 'dark',
    });

    final persistence = PersistenceService();
    final loaded = await persistence.loadConversations();
    expect(loaded.map((c) => c.id).toSet(), {'legacy1', 'legacy2'});
    expect(await persistence.loadThemeMode(), 'dark');

    // A second load doesn't re-run migration or duplicate records, even if
    // a migrated record has since been deleted.
    await persistence.deleteConversation('legacy1');
    final reloaded = await persistence.loadConversations();
    expect(reloaded.map((c) => c.id).toList(), ['legacy2']);
  });

  test('saveConversation writes per-record; delete removes only that one',
      () async {
    SharedPreferences.setMockInitialValues({});
    final persistence = PersistenceService();

    await persistence.saveConversation(_conversation('a'));
    await persistence.saveConversation(_conversation('b'));
    await persistence
        .saveConversation(_conversation('a')); // overwrite, not duplicate

    expect((await persistence.loadConversations()), hasLength(2));

    await persistence.deleteConversation('a');
    final remaining = await persistence.loadConversations();
    expect(remaining.single.id, 'b');
  });

  test('loadConversations returns newest-updated first', () async {
    SharedPreferences.setMockInitialValues({});
    final persistence = PersistenceService();
    await persistence.saveConversation(
        _conversation('old', updatedAt: DateTime(2026, 1, 1)));
    await persistence.saveConversation(
        _conversation('new', updatedAt: DateTime(2026, 7, 1)));

    final loaded = await persistence.loadConversations();
    expect(loaded.first.id, 'new');
  });

  test('assets round-trip and prune oldest past the cap', () async {
    SharedPreferences.setMockInitialValues({});
    final persistence = PersistenceService();

    for (var i = 0; i < PersistenceService.maxStoredAssets + 3; i++) {
      await persistence.saveAsset(
          'asset-$i', Uint8List.fromList([i, i, i]));
    }

    // Newest survive, oldest three were pruned.
    final newest = await persistence
        .loadAsset('asset-${PersistenceService.maxStoredAssets + 2}');
    expect(newest, isNotNull);
    expect(await persistence.loadAsset('asset-0'), isNull);
    expect(await persistence.loadAsset('asset-2'), isNull);
    expect(await persistence.loadAsset('asset-3'), isNotNull);
  });

  test('projects and user prefs persist through the kv store', () async {
    SharedPreferences.setMockInitialValues({});
    final persistence = PersistenceService();

    await persistence.saveUserPrefs({'nickname': 'Nate'});
    expect((await persistence.loadUserPrefs())['nickname'], 'Nate');
  });
}
