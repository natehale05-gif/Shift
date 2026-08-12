import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shift/core/design/ghost.dart';
import 'package:shift/core/design/metrics.dart';
import 'package:shift/core/design/theme.dart';
import 'package:shift/data/agent_store.dart';
import 'package:shift/data/api_keys_store.dart';
import 'package:shift/data/artifact_store.dart';
import 'package:shift/data/asset_store.dart';
import 'package:shift/data/conversation_store.dart';
import 'package:shift/data/image_store.dart';
import 'package:shift/data/kv_store.dart';
import 'package:shift/data/note_store.dart';
import 'package:shift/features/chat/private_banner.dart';
import 'package:shift/features/chat/private_toggle.dart';
import 'package:shift/features/chat/turn_controller.dart';
import 'package:shift/features/design/design_turns.dart';
import 'package:shift/features/notes/note_cleaner.dart';
import 'package:shift/features/visual/visual_turns.dart';
import 'package:shift/features/work/work_runner.dart';
import 'package:shift/shell/app_shell.dart';
import 'package:shift/shell/mode.dart';
import 'package:shift/shell/shell_controller.dart';

/// The ghost in the top bar.
///
/// Driven through the real [AppShell] rather than the toggle on its own: the
/// two things worth pinning are *where it appears* and *which modes get it*,
/// and neither is observable from the widget in isolation.
void main() {
  Widget app({
    required ShellController shell,
    required TurnController turn,
    Brightness brightness = Brightness.light,
  }) =>
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: shell),
          ChangeNotifierProvider.value(value: turn),
          ChangeNotifierProvider(create: (_) => ApiKeysStore(KvStore())),
          ChangeNotifierProvider(create: (_) => ConversationStore(KvStore())),
          ChangeNotifierProvider(create: (_) => AgentStore(KvStore())),
          ChangeNotifierProvider(create: (_) => WorkAgents(KvStore())),
          ChangeNotifierProvider(create: (_) => NoteStore(KvStore())),
          ChangeNotifierProvider(create: (_) => NoteCleaner()),
          ChangeNotifierProvider(
            create: (_) => ImageStore(KvStore(), AssetStore()),
          ),
          ChangeNotifierProvider(
            create: (_) => DesignTurns(
              keys: ApiKeysStore(KvStore()),
              conversations: ConversationStore(KvStore()),
              artifacts: ArtifactStore(KvStore()),
            ),
          ),
          ChangeNotifierProvider(
            create: (_) => VisualTurns(
              keys: ApiKeysStore(KvStore()),
              images: ImageStore(KvStore(), AssetStore()),
            ),
          ),
        ],
        child: MaterialApp(
          theme: shiftTheme(brightness, TargetPlatform.linux),
          home: const AppShell(),
        ),
      );

  /// Pumps the shell wide enough that the sidebar is beside the content, so
  /// both it and the top bar can be asserted in one tree.
  Future<({ShellController shell, TurnController turn})> pump(
    WidgetTester tester, {
    Size logical = const Size(1280, 900),
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = logical;
    addTearDown(tester.view.reset);

    final shell = ShellController();
    final turn = TurnController();
    addTearDown(turn.dispose);
    addTearDown(shell.dispose);

    await tester.pumpWidget(
        app(shell: shell, turn: turn, brightness: brightness));
    await tester.pumpAndSettle();
    return (shell: shell, turn: turn);
  }

  /// The toggle's own ghost.
  ///
  /// Scoped, because the banner carries the same mark: an unscoped
  /// `find.byType(GhostIcon)` matches two of them the moment a chat is
  /// private, which is exactly the state most of these tests are in.
  GhostIcon ghost(WidgetTester tester) => tester.widget<GhostIcon>(
        find.descendant(
          of: find.byType(PrivateChatToggle),
          matching: find.byType(GhostIcon),
        ),
      );

  group('where it is', () {
    testWidgets('in the top bar in Chat', (tester) async {
      await pump(tester);
      expect(find.byType(PrivateChatToggle), findsOneWidget);

      // Top right: past the middle of the window, and above the conversation.
      final box = tester.getRect(find.byType(PrivateChatToggle));
      expect(box.center.dx, greaterThan(1280 / 2));
      expect(box.top, lessThan(60));
    });

    testWidgets('absent in the other five', (tester) async {
      // Not "hidden": absent. A control that is present but inert invites a
      // tap and then answers nothing, which is worse than not offering it.
      final (:shell, :turn) = await pump(tester);

      for (final mode in AppMode.values.where((m) => m != AppMode.chat)) {
        shell.openMode(mode);
        await tester.pumpAndSettle();
        expect(find.byType(PrivateChatToggle), findsNothing,
            reason: mode.label);
      }

      shell.openMode(AppMode.chat);
      await tester.pumpAndSettle();
      expect(find.byType(PrivateChatToggle), findsOneWidget);
    });

    testWidgets('it clears the touch minimum', (tester) async {
      await pump(tester);
      final size = tester.getSize(find.byType(PrivateChatToggle));
      expect(size.height, greaterThanOrEqualTo(kMinTouchTarget));
      expect(size.width, greaterThanOrEqualTo(kMinTouchTarget));
    });

    testWidgets('the sidebar no longer offers a second way in', (tester) async {
      // Two controls for one setting is the redundancy this replaced, and the
      // sidebar's row is the one that went.
      await pump(tester);
      expect(find.text('New chat'), findsOneWidget);
      expect(find.text('Private chat'), findsNothing);
    });
  });

  group('what a tap does', () {
    testWidgets('turns a chat private, and says so', (tester) async {
      final (:shell, :turn) = await pump(tester);
      expect(turn.private, isFalse);
      expect(find.byType(PrivateBanner), findsNothing);

      await tester.tap(find.byType(PrivateChatToggle));
      await tester.pumpAndSettle();

      expect(turn.private, isTrue);
      expect(find.byType(PrivateBanner), findsOneWidget);
    });

    testWidgets('turning it off starts a fresh chat, not just a flag flip',
        (tester) async {
      // The distinction is the whole design: privacy belongs to a
      // conversation, so leaving one means leaving it — not converting it.
      final (:shell, :turn) = await pump(tester);
      turn.clear(private: true);
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PrivateChatToggle));
      await tester.pumpAndSettle();

      expect(turn.private, isFalse);
      expect(turn.items, isEmpty);
      expect(find.byType(PrivateBanner), findsNothing);
    });

    testWidgets('an empty private chat is left without a prompt',
        (tester) async {
      // Confirming nothing away is how people learn to dismiss prompts, and
      // the next one they dismiss is the one that mattered.
      final (:shell, :turn) = await pump(tester);
      turn.clear(private: true);
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PrivateChatToggle));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(turn.private, isFalse);
    });
  });

  group('leaving a private chat that has something in it', () {
    Future<TurnController> withMessages(WidgetTester tester) async {
      final (:shell, :turn) = await pump(tester);
      turn.clear(private: true);
      turn.items.add(const UserSaid('something I would rather not keep'));
      await tester.pumpAndSettle();
      return turn;
    }

    testWidgets('asks first', (tester) async {
      final turn = await withMessages(tester);

      await tester.tap(find.byType(PrivateChatToggle));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Leave this private chat?'), findsOneWidget);
      // Still private, still there — the dialog has not been answered.
      expect(turn.private, isTrue);
      expect(turn.items, hasLength(1));
    });

    testWidgets('cancelling leaves it exactly as it was', (tester) async {
      final turn = await withMessages(tester);

      await tester.tap(find.byType(PrivateChatToggle));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(turn.private, isTrue);
      expect(turn.items, hasLength(1));
      expect(ghost(tester).filled, isTrue);
    });

    testWidgets('confirming discards it', (tester) async {
      final turn = await withMessages(tester);

      await tester.tap(find.byType(PrivateChatToggle));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Leave'));
      await tester.pumpAndSettle();

      expect(turn.private, isFalse);
      expect(turn.items, isEmpty);
    });
  });

  group('the glyph', () {
    testWidgets('is filled when private and outline when not', (tester) async {
      // Read off the shape rather than off a colour: the toggle has to be
      // legible in light, dark and Code mode's near-black, and a test that
      // asserted a hue would pass for the wrong reason in two of them.
      await pump(tester);
      expect(ghost(tester).filled, isFalse);

      await tester.tap(find.byType(PrivateChatToggle));
      await tester.pumpAndSettle();
      expect(ghost(tester).filled, isTrue);
    });

    testWidgets('takes its ink from the theme, in both', (tester) async {
      for (final brightness in Brightness.values) {
        await pump(tester, brightness: brightness);
        final off = ghost(tester).color;

        await tester.tap(find.byType(PrivateChatToggle));
        await tester.pumpAndSettle();

        // The on state is the accent and the off state is not, whichever
        // theme is running — so "it is lit" is visible as well as shaped.
        expect(ghost(tester).color, isNot(off), reason: '$brightness');
      }
    });
  });
}
