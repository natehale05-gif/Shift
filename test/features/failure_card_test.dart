import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shift/core/design/theme.dart';
import 'package:shift/data/api_keys_store.dart';
import 'package:shift/data/conversation_store.dart';
import 'package:shift/data/kv_store.dart';
import 'package:shift/data/update_store.dart';
import 'package:shift/features/chat/chat_surface.dart';
import 'package:shift/features/chat/failure_card.dart';
import 'package:shift/features/chat/message_actions.dart';
import 'package:shift/features/chat/turn_controller.dart';
import 'package:shift/shell/app_shell.dart';
import 'package:shift/shell/mode.dart';
import 'package:shift/shell/shell_controller.dart';

/// What a failed reply offers the person reading it.
///
/// Both assertions here are of controls that did not exist: the disclosure that
/// makes a screenshot diagnostic, and the retry that was hidden in exactly the
/// case where it is the obvious next move.
void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('shift-failure');
  });
  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Widget host(TurnController turn) => MultiProvider(
        providers: [ChangeNotifierProvider.value(value: turn)],
        child: MaterialApp(
          theme: shiftTheme(Brightness.light, TargetPlatform.iOS),
          home: const Scaffold(body: ChatSurface()),
        ),
      );

  /// A controller holding one failed exchange, with no engine behind it.
  TurnController failed({String? detail, String text = ''}) {
    final turn = TurnController(executors: () => const {});
    turn.items
      ..add(const UserSaid('hello'))
      ..add(Reply()
        ..write(text)
        ..failure = 'The request was blocked before it reached the provider.'
        ..failureDetail = detail
        ..done = true);
    return turn;
  }

  testWidgets('the detail is hidden until asked for, then shown', (t) async {
    final turn = failed(detail: 'ClientException: Failed to fetch · host');
    addTearDown(turn.dispose);
    await t.pumpWidget(host(turn));

    expect(find.byType(FailureCard), findsOneWidget);
    // Collapsed: this is for a bug report, not for reading. Inline it would be
    // noise on every failure, which is how people learn to ignore the card.
    expect(find.textContaining('Failed to fetch'), findsNothing);

    await t.tap(find.text('Details'));
    await t.pumpAndSettle();

    expect(find.textContaining('Failed to fetch'), findsOneWidget);
  });

  testWidgets('a failure with nothing to disclose offers no disclosure',
      (t) async {
    final turn = failed();
    addTearDown(turn.dispose);
    await t.pumpWidget(host(turn));

    expect(find.text('Details'), findsNothing);
  });

  testWidgets('a failed reply can be tried again', (t) async {
    // It could not before: the actions row was gated on `failure == null`, so
    // the one case where retrying is obvious was the one case with no button
    // for it, and the remedy was to retype the message.
    //
    // Driven through `send` rather than assembled by hand, because retry is
    // only offered once there is a request to repeat.
    final turn = TurnController(executors: () => const {});
    addTearDown(turn.dispose);
    await turn.send('hello', mode: AppMode.chat);
    await t.pumpWidget(host(turn));

    expect(turn.items.whereType<Reply>().single.failure, isNotNull);
    expect(find.byType(MessageActions), findsOneWidget);
    expect(find.byTooltip('Try again'), findsOneWidget);
  });

  testWidgets('a failed reply offers no copy, having nothing to copy',
      (t) async {
    final turn = failed();
    addTearDown(turn.dispose);
    await t.pumpWidget(host(turn));

    expect(find.byTooltip('Copy'), findsNothing);
  });

  testWidgets('choosing a conversation on a phone closes the drawer',
      (t) async {
    // Found by driving the real build: the drawer stayed open over the
    // conversation it had just opened, so on a phone picking a chat looked
    // like nothing happened. `Sidebar` always had the hook; the drawer was
    // the one caller not passing it.
    t.view.devicePixelRatio = 1.0;
    t.view.physicalSize = const Size(393, 852);
    addTearDown(t.view.reset);

    // `runAsync`, because a widget test's zone fakes time: a real file write
    // never completes inside it, and the test hangs rather than failing.
    final store = ConversationStore(KvStore(path: '${dir.path}/settings.json'));
    await t.runAsync(() async {
      await store.load();
      await store.save(id: 'c1', title: 'a saved chat', items: const []);
    });

    final turn = TurnController(conversations: store);
    addTearDown(turn.dispose);

    await t.pumpWidget(MultiProvider(
      providers: [
        // The shell renders `UpdateBanner`, which reads this. Idle and never
        // loaded here, so it does no I/O and draws nothing.
        ChangeNotifierProvider(create: (_) => UpdateStore(KvStore())),
        ChangeNotifierProvider.value(value: turn),
        ChangeNotifierProvider.value(value: store),
        ChangeNotifierProvider(create: (_) => ShellController()),
        ChangeNotifierProvider(create: (_) => ApiKeysStore(KvStore())),
      ],
      child: MaterialApp(
        theme: shiftTheme(Brightness.light, TargetPlatform.iOS),
        home: const AppShell(),
      ),
    ));

    await t.tap(find.byIcon(Icons.menu_rounded));
    await t.pumpAndSettle();
    expect(find.text('a saved chat'), findsOneWidget);

    await t.tap(find.text('a saved chat'));
    await t.pumpAndSettle();

    expect(find.byType(Drawer), findsNothing);
  });
}
