import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shift_ai/data/persistence/persistence_service.dart';
import 'package:shift_ai/data/stores/conversation_store.dart';
import 'package:shift_ai/data/stores/memory_store.dart';
import 'package:shift_ai/data/stores/project_store.dart';
import 'package:shift_ai/data/stores/styles_store.dart';
import 'package:shift_ai/data/stores/user_prefs_store.dart';
import 'package:shift_ai/features/chat/composer/composer_options.dart';
import 'package:shift_ai/turn/backends/mock_backend.dart';

/// The style-resolution rule used to live inside `_ChatInputBarState`, where it
/// could only be reached by pumping the whole composer. Extracted, it is a
/// plain object and these are plain assertions.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PersistenceService persistence;
  late UserPrefsStore prefs;
  late ProjectStore projects;
  late ConversationStore conversations;
  late MemoryStore memory;
  late StylesStore styles;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    persistence = PersistenceService();
    prefs = UserPrefsStore(persistence: persistence);
    projects = ProjectStore(persistence: persistence);
    conversations = ConversationStore(
      chatService: MockChatService(),
      persistence: persistence,
    );
    memory = MemoryStore(persistence: persistence);
    styles = StylesStore(persistence: persistence);
    await styles.load();
    await memory.load();
  });

  ComposerOptions freshOptions() => ComposerOptions();

  Future<dynamic> build(ComposerOptions o) async => o.build(
        prefs: prefs,
        projects: projects,
        conversations: conversations,
        memory: memory,
        styles: styles,
      );

  test('defaults carry no pin and leave thinking on', () async {
    final options = await build(freshOptions());
    expect(options.modelPin, isNull);
    expect(options.extendedThinking, isTrue);
    expect(options.webSearch, isFalse);
    expect(options.deepResearch, isFalse);
  });

  test('tool toggles and the model pin pass straight through', () async {
    final o = freshOptions()
      ..modelPin = 'claude-opus-4-8'
      ..webSearch = true
      ..deepResearch = true
      ..codeExecution = true
      ..extendedThinking = false;
    final options = await build(o);
    expect(options.modelPin, 'claude-opus-4-8');
    expect(options.webSearch, isTrue);
    expect(options.deepResearch, isTrue);
    expect(options.codeExecution, isTrue);
    expect(options.extendedThinking, isFalse);
  });

  test('a built-in style selects its own clause by id', () async {
    prefs.setResponseStyle('concise');
    final options = await build(freshOptions());
    expect(options.systemPrompt, contains('Style:'));
    expect(options.systemPrompt, contains('short and direct'));
  });

  test('the default style adds no clause at all', () async {
    prefs.setResponseStyle('normal');
    final options = await build(freshOptions());
    expect(options.systemPrompt, isNot(contains('Style:')));
  });

  test('a custom style overrides the built-in clause instead of stacking',
      () async {
    final style = styles.create('Pirate', 'Answer like a pirate.');
    prefs.setResponseStyle(style.id);
    final options = await build(freshOptions());
    // A custom style reports itself as 'normal' and passes its own text, so
    // the built-in concise/explanatory/formal clauses cannot also apply.
    expect(options.systemPrompt, contains('Answer like a pirate.'));
    expect(options.systemPrompt, isNot(contains('short and direct')));
  });

  test('a custom style replaces a built-in one that was set before it', () {
    // One setting holds both kinds of id, so selecting a custom style has to
    // displace the built-in rather than layer over it.
    prefs.setResponseStyle('formal');
    final style = styles.create('Pirate', 'Answer like a pirate.');
    prefs.setResponseStyle(style.id);
    expect(prefs.responseStyle, style.id);
  });

  test('personalization reaches the system prompt', () async {
    prefs.setNickname('Nate');
    prefs.setRole('Founder');
    final options = await build(freshOptions());
    expect(options.systemPrompt, contains('Nate'));
    expect(options.systemPrompt, contains('Founder'));
  });
}
