import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shift_ai/data/models/chat_message.dart';
import 'package:shift_ai/turn/backends/mock_backend.dart';
import 'package:shift_ai/data/persistence/persistence_service.dart';
import 'package:shift_ai/data/stores/api_keys_store.dart';
import 'package:shift_ai/data/stores/conversation_store.dart';
import 'package:shift_ai/core/theme/app_theme.dart';
import 'package:shift_ai/data/models/message_block.dart';
import 'package:shift_ai/features/chat/message/message_view.dart';
import 'package:shift_ai/data/models/studio_type.dart';
import 'package:shift_ai/features/chat/message/building_indicator.dart';
import 'package:shift_ai/features/chat/message/typing_indicator.dart';

const _markdownFixture = '''
# Release notes

Some **bold** intro prose with `inline_code` in it.

```python
def greet(name):
    return f"Hello, {name}"
```

| Feature | Status |
|---------|--------|
| Chat    | Done   |
| Voice   | Soon   |
''';

ChatMessage _assistantMessage(String text) => ChatMessage(
      id: 'm1',
      conversationId: 'c1',
      role: MessageRole.assistant,
      text: text,
      timestamp: DateTime(2026, 7, 19, 12, 0),
    );

Widget _harness(Widget child) => MultiProvider(
      providers: [
        // The action row's Regenerate menu reads keyed providers; the user
        // bubble reads the store for edit-branch info.
        ChangeNotifierProvider(
            create: (_) => ApiKeysStore(persistence: PersistenceService())),
        ChangeNotifierProvider(
          create: (_) => ConversationStore(
            chatService: MockChatService(),
            persistence: PersistenceService(),
          ),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('assistant markdown renders heading, code block, and table',
      (tester) async {
    await tester.pumpWidget(
      _harness(MessageView(message: _assistantMessage(_markdownFixture))),
    );
    await tester.pumpAndSettle();

    // Heading and bold prose render as text (not raw markdown syntax).
    expect(find.textContaining('Release notes'), findsOneWidget);
    expect(find.textContaining('# Release notes'), findsNothing);

    // Fenced code block renders with its language label and contents.
    expect(find.text('python'), findsOneWidget);
    expect(
      find.textContaining('def greet(name):', findRichText: true),
      findsOneWidget,
    );

    // Table cells render individually.
    expect(find.text('Feature'), findsOneWidget);
    expect(find.text('Voice'), findsOneWidget);
  });

  testWidgets('user message renders as a plain bubble without markdown',
      (tester) async {
    final message = ChatMessage(
      id: 'm2',
      conversationId: 'c1',
      role: MessageRole.user,
      text: 'please **do not** format this',
      timestamp: DateTime(2026, 7, 19, 12, 0),
    );
    await tester.pumpWidget(_harness(MessageView(message: message)));
    await tester.pumpAndSettle();

    // The literal asterisks survive: user text is never markdown-parsed.
    expect(find.text('please **do not** format this'), findsOneWidget);
  });

  testWidgets('the same indicator covers a wait that is only thinking',
      (tester) async {
    // Thinking is collapsed behind a disclosure, so a message holding nothing
    // else looked idle. Every studio now waits the same way instead of
    // announcing itself in its own prose.
    final message = ChatMessage(
      id: 'm3',
      conversationId: 'c1',
      role: MessageRole.assistant,
      text: '',
      status: MessageStatus.streaming,
      blocks: const [ThinkingBlock('Parsing the request.')],
      timestamp: DateTime(2026, 7, 30, 12, 0),
    );
    await tester.pumpWidget(_harness(MessageView(message: message)));
    await tester.pump();

    expect(find.byType(TypingIndicator), findsOneWidget);
  });

  testWidgets('real content replaces the indicator', (tester) async {
    final message = ChatMessage(
      id: 'm4',
      conversationId: 'c1',
      role: MessageRole.assistant,
      text: 'Here you go:',
      status: MessageStatus.streaming,
      blocks: const [
        ThinkingBlock('Parsing the request.'),
        TextBlock('Here you go:'),
      ],
      timestamp: DateTime(2026, 7, 30, 12, 0),
    );
    await tester.pumpWidget(_harness(MessageView(message: message)));
    await tester.pump();

    expect(find.byType(TypingIndicator), findsNothing);
  });

  testWidgets('the tool keeps working while the code is being written',
      (tester) async {
    // The long part of a build is after the prose: a code turn opens with a
    // sentence and then writes the file, which is withheld from the transcript
    // so the page does not arrive twice. The screen used to go completely
    // still for exactly the stretch when the thing was being made.
    final message = ChatMessage(
      id: 'm5',
      conversationId: 'c1',
      role: MessageRole.assistant,
      text: "Here's a coffee shop site:",
      status: MessageStatus.streaming,
      studioType: StudioType.codeStudio,
      blocks: const [TextBlock("Here's a coffee shop site:")],
      timestamp: DateTime(2026, 7, 30, 12, 0),
    );
    await tester.pumpWidget(_harness(MessageView(message: message)));
    await tester.pump();

    expect(find.byType(BuildingIndicator), findsOneWidget);
    expect(find.text('Building'), findsOneWidget);
    expect(find.byType(TypingIndicator), findsNothing,
        reason: 'content has arrived; the dots have had their turn');
  });

  testWidgets('it stops once the turn is finished', (tester) async {
    final message = ChatMessage(
      id: 'm6',
      conversationId: 'c1',
      role: MessageRole.assistant,
      text: 'Done.',
      status: MessageStatus.complete,
      studioType: StudioType.codeStudio,
      blocks: const [TextBlock('Done.')],
      timestamp: DateTime(2026, 7, 30, 12, 0),
    );
    await tester.pumpWidget(_harness(MessageView(message: message)));
    await tester.pump();

    expect(find.byType(BuildingIndicator), findsNothing);
  });

  testWidgets('a plain answer streams without a tool under it',
      (tester) async {
    // The hammer would be a lie over a turn that is only writing prose.
    final message = ChatMessage(
      id: 'm7',
      conversationId: 'c1',
      role: MessageRole.assistant,
      text: 'The capital of France is Paris.',
      status: MessageStatus.streaming,
      studioType: StudioType.middleware,
      blocks: const [TextBlock('The capital of France is Paris.')],
      timestamp: DateTime(2026, 7, 30, 12, 0),
    );
    await tester.pumpWidget(_harness(MessageView(message: message)));
    await tester.pump();

    expect(find.byType(BuildingIndicator), findsNothing);
    expect(find.byType(TypingIndicator), findsNothing);
  });

  testWidgets('an image turn shows one pencil, not two', (tester) async {
    final message = ChatMessage(
      id: 'm8',
      conversationId: 'c1',
      role: MessageRole.assistant,
      text: 'Drawing that now:',
      status: MessageStatus.streaming,
      studioType: StudioType.imageStudio,
      blocks: const [TextBlock('Drawing that now:')],
      timestamp: DateTime(2026, 7, 30, 12, 0),
    );
    await tester.pumpWidget(_harness(MessageView(message: message)));
    await tester.pump();

    expect(find.byType(BuildingIndicator), findsOneWidget);
    expect(find.text('Drawing'), findsOneWidget);
  });
}
