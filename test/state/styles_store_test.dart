import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shift_ai/data/persistence/persistence_service.dart';
import 'package:shift_ai/services/prompt_assembler.dart';
import 'package:shift_ai/data/stores/styles_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('StylesStore creates, labels, edits, removes, and persists', () async {
    SharedPreferences.setMockInitialValues({});
    final persistence = PersistenceService();
    final store = StylesStore(persistence: persistence);
    await store.load();

    final style = store.create('Socratic', 'Answer with guiding questions.');
    expect(store.customStyles, hasLength(1));
    expect(store.labelFor(style.id), 'Socratic');
    // Built-ins resolve too.
    expect(store.labelFor('formal'), 'Formal');
    expect(isBuiltInStyle('normal'), isTrue);
    expect(isBuiltInStyle(style.id), isFalse);

    store.update(style.id, name: 'Coach');
    expect(store.styleById(style.id)!.name, 'Coach');

    await Future<void>.delayed(const Duration(milliseconds: 20));
    final reloaded = StylesStore(persistence: persistence);
    await reloaded.load();
    expect(reloaded.styleById(style.id)?.name, 'Coach');

    store.remove(style.id);
    expect(store.customStyles, isEmpty);
  });

  test('a custom style instruction overrides the built-in style clause', () {
    final prompt = assembleSystemPrompt(
      responseStyle: 'concise',
      styleInstruction: 'Reply only in rhyming couplets.',
    );
    expect(prompt, contains('Reply only in rhyming couplets.'));
    // The built-in concise clause is suppressed when a custom style is active.
    expect(prompt.contains('short and direct'), isFalse);
  });
}
