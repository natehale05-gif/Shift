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
import 'package:shift_ai/features/chat/message/message_view.dart';

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
}
