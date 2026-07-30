import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shift_ai/data/persistence/persistence_service.dart';
import 'package:shift_ai/turn/prompt_assembler.dart';
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

  test('a custom style is resolved exactly like a built-in', () async {
    SharedPreferences.setMockInitialValues({});
    final store = StylesStore(persistence: PersistenceService());
    await store.load();
    final style = store.create('Rhyming', 'Reply only in rhyming couplets.');

    // One lookup, one clause — the composer no longer has to work out which
    // kind of style it was handed before assembling the prompt.
    final custom = assembleSystemPrompt(
      styleInstruction: store.styleById(style.id)!.instructions,
    );
    expect(custom, contains('Style: Reply only in rhyming couplets.'));
    expect(custom.contains('short and direct'), isFalse);
  });

  test('every built-in produces the clause it always produced', () {
    // This wave is a refactor: the same style must yield the same prompt text
    // it did when the clauses lived in a switch inside assembleSystemPrompt.
    String promptFor(String id) => assembleSystemPrompt(
        styleInstruction:
            builtInStyles.firstWhere((s) => s.id == id).instructions);

    expect(
      promptFor('concise'),
      contains('Style: keep responses short and direct — lead with the '
          'answer, minimal preamble.'),
    );
    expect(
      promptFor('explanatory'),
      contains('Style: give thorough, well-structured responses that teach — '
          'explain the reasoning and include helpful examples.'),
    );
    expect(
      promptFor('formal'),
      contains('Style: write in a polished, professional register — complete '
          'sentences, no slang or emoji.'),
    );
    expect(promptFor('normal').contains('Style:'), isFalse);
  });

  test('an id nothing answers to degrades to Normal', () async {
    // What a style deleted while selected leaves behind.
    SharedPreferences.setMockInitialValues({});
    final store = StylesStore(persistence: PersistenceService());
    await store.load();

    expect(store.styleById('a-style-that-was-deleted'), isNull);
    final prompt = assembleSystemPrompt(
        styleInstruction: store.styleById('a-style-that-was-deleted')
                ?.instructions ??
            '');
    expect(prompt.contains('Style:'), isFalse);
  });
}
