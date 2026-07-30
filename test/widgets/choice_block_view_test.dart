import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shift_ai/core/theme/app_theme.dart';
import 'package:shift_ai/core/theme/tap_targets.dart';
import 'package:shift_ai/data/models/message_block.dart';
import 'package:shift_ai/data/persistence/persistence_service.dart';
import 'package:shift_ai/data/stores/conversation_store.dart';
import 'package:shift_ai/features/chat/message/choice_block_view.dart';
import 'package:shift_ai/turn/backends/mock_backend.dart';

const _unanswered = ChoiceBlock(
  id: 'q1',
  question: 'Which platform?',
  options: ['TikTok', 'Email'],
);

Future<Widget> _host(ChoiceBlock block) async {
  SharedPreferences.setMockInitialValues({});
  final store = ConversationStore(
    chatService: MockChatService(),
    persistence: PersistenceService(),
  );
  return ChangeNotifierProvider<ConversationStore>.value(
    value: store,
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: ChoiceBlockView(block: block, messageId: 'm1'),
      ),
    ),
  );
}

void main() {
  testWidgets('the question and every option are on screen', (tester) async {
    await tester.pumpWidget(await _host(_unanswered));

    expect(find.text('Which platform?'), findsOneWidget);
    expect(find.text('TikTok'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
  });

  testWidgets('every option clears the minimum tap target', (tester) async {
    // These are the most-tapped thing in a turn that offers them; a chip that
    // is comfortable with a mouse can still be a miss with a thumb.
    await tester.pumpWidget(await _host(_unanswered));

    final chips = find.byType(InkWell);
    expect(chips, findsNWidgets(2));
    for (final element in chips.evaluate()) {
      final size = tester.getSize(find.byWidget(element.widget));
      expect(size.height, greaterThanOrEqualTo(kMinTouchTarget));
      expect(size.width, greaterThanOrEqualTo(kMinTouchTarget));
    }
  });

  testWidgets('an answered question stays on screen but cannot be answered '
      'again', (tester) async {
    await tester.pumpWidget(await _host(_unanswered.withChoice(['Email'])));

    // The question and the pick are still readable — removing it would erase
    // the context the answer belongs to.
    expect(find.text('Which platform?'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);

    for (final inkWell in tester.widgetList<InkWell>(find.byType(InkWell))) {
      expect(inkWell.onTap, isNull);
    }
  });

  testWidgets('a single-select question has no Send button — the tap is the '
      'answer', (tester) async {
    await tester.pumpWidget(await _host(_unanswered));
    expect(find.text('Send'), findsNothing);
  });

  testWidgets('tapping a single-select option marks it and locks the rest',
      (tester) async {
    // The answered block is left on screen to say what was picked, so the
    // pick has to be visible on it — a tick, and nothing else still tappable.
    await tester.pumpWidget(await _host(_unanswered));

    await tester.tap(find.text('TikTok'));
    await tester.pump();

    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    for (final inkWell in tester.widgetList<InkWell>(find.byType(InkWell))) {
      expect(inkWell.onTap, isNull);
    }
  });

  testWidgets('a multi-select question commits with Send, disabled until '
      'something is picked', (tester) async {
    const multi = ChoiceBlock(
      id: 'q1',
      question: 'Which platforms?',
      options: ['TikTok', 'Email'],
      multiSelect: true,
    );
    await tester.pumpWidget(await _host(multi));

    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);

    await tester.tap(find.text('TikTok'));
    await tester.pump();

    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull);
  });
}
