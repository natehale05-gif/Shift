import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shift/core/design/metrics.dart';
import 'package:shift/core/design/theme.dart';
import 'package:shift/data/api_keys_store.dart';
import 'package:shift/data/artifact_store.dart';
import 'package:shift/data/asset_store.dart';
import 'package:shift/data/image_store.dart';
import 'package:shift/data/agent_store.dart';
import 'package:shift/data/conversation_store.dart';
import 'package:shift/data/kv_store.dart';
import 'package:shift/data/note_store.dart';
import 'package:shift/features/notes/note_cleaner.dart';
import 'package:shift/features/chat/chat_surface.dart';
import 'package:shift/features/code/code_surface.dart';
import 'package:shift/features/notes/notes_surface.dart';
import 'package:shift/features/chat/turn_controller.dart';
import 'package:shift/features/design/design_surface.dart';
import 'package:shift/features/design/design_turns.dart';
import 'package:shift/features/visual/visual_surface.dart';
import 'package:shift/features/visual/visual_turns.dart';
import 'package:shift/shell/app_shell.dart';
import 'package:shift/shell/mode.dart';
import 'package:shift/features/work/work_runner.dart';
import 'package:shift/features/work/work_surface.dart';
import 'package:shift/shell/mode_menu.dart';
import 'package:shift/shell/shell_controller.dart';

Widget _app({
  required Brightness brightness,
  required TargetPlatform platform,
  ShellController? controller,
}) =>
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: controller ?? ShellController()),
        ChangeNotifierProvider(create: (_) => ApiKeysStore(KvStore())),
        ChangeNotifierProvider(create: (_) => ConversationStore(KvStore())),
        ChangeNotifierProvider(create: (_) => TurnController()),
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
        // The platform travels through the theme rather than through
        // `debugDefaultTargetPlatformOverride`, because the global is a
        // foundation debug variable the test framework asserts is unset by the
        // time a test body ends, which `addTearDown` is too late to satisfy.
        theme: shiftTheme(brightness, platform),
        home: const AppShell(),
      ),
    );

Future<void> _pumpAt(
  WidgetTester tester, {
  required Size logical,
  required TargetPlatform platform,
  Brightness brightness = Brightness.light,
  ShellController? controller,
}) async {
  // At a device pixel ratio of 1 the physical and logical sizes are the same
  // number, which keeps the cases below readable as the sizes people quote.
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = logical;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app(
      brightness: brightness, platform: platform, controller: controller));
  await tester.pumpAndSettle();
}

/// Opens the mode menu and waits for it.
Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byType(ModeMenu));
  await tester.pumpAndSettle();
}

const _phone = (Size(393, 852), TargetPlatform.iOS);
const _desktop = (Size(1280, 900), TargetPlatform.linux);

void main() {
  group('the mode menu', () {
    testWidgets('shows the current mode, and only that, until it is opened',
        (tester) async {
      await _pumpAt(tester, logical: _phone.$1, platform: _phone.$2);

      expect(find.byType(ModeMenu), findsOneWidget);

      // The five other modes are not on screen until asked for. That is the
      // point of the change: the row it replaced kept two of six permanently
      // off the right edge, visible only to someone who thought to scroll.
      expect(find.text(AppMode.notes.label), findsNothing);
    });

    testWidgets('opening it offers all six', (tester) async {
      await _pumpAt(tester, logical: _phone.$1, platform: _phone.$2);
      await _openMenu(tester);

      for (final mode in AppMode.values) {
        expect(find.text(mode.label), findsWidgets, reason: mode.label);
      }
    });

    testWidgets('the same control on a phone and a desktop', (tester) async {
      // One switcher everywhere, which is the other half of the change: there
      // used to be a rail here and a scrolling row there.
      for (final (logical, platform) in [_phone, _desktop]) {
        await _pumpAt(tester, logical: logical, platform: platform);
        expect(find.byType(ModeMenu), findsOneWidget, reason: '$platform');
      }
    });

    testWidgets('each entry says what its mode is for', (tester) async {
      // A menu is where someone decides where to go, and "Work" on its own
      // does not tell anyone why they would.
      await _pumpAt(tester, logical: _desktop.$1, platform: _desktop.$2);
      await _openMenu(tester);

      expect(find.text(AppMode.work.menuHint), findsWidgets);
    });
  });

  group('modes', () {
    testWidgets('every mode is reachable and opens its own surface',
        (tester) async {
      await _pumpAt(tester, logical: _desktop.$1, platform: _desktop.$2);

      for (final mode in AppMode.values) {
        await _openMenu(tester);
        await tester.tap(find.text(mode.label).last);
        await tester.pumpAndSettle();

        // Every mode now has a surface of its own — there is no placeholder
        // arm left, and a `Type` per mode is what makes that a fact the test
        // states rather than a gap it papers over.
        expect(
          find.byType(switch (mode) {
            AppMode.chat => ChatSurface,
            AppMode.code => CodeSurface,
            AppMode.notes => NotesSurface,
            AppMode.visual => VisualSurface,
            AppMode.design => DesignSurface,
            AppMode.work => WorkSurface,
          }),
          findsOneWidget,
          reason: mode.label,
        );
      }
    });

    testWidgets('chat is where the app opens', (tester) async {
      // A product decision — ask for anything, get it back — so it is pinned
      // rather than left to enum ordering.
      await _pumpAt(tester, logical: _desktop.$1, platform: _desktop.$2);
      expect(find.byType(ChatSurface), findsOneWidget);
    });

    testWidgets('a mode set from outside the widget tree is reflected',
        (tester) async {
      // Siri, a Shortcut and a deep link all set the mode without anyone
      // touching the menu, and the trigger has to agree with the body.
      final controller = ShellController();
      addTearDown(controller.dispose);
      await _pumpAt(tester,
          logical: _phone.$1, platform: _phone.$2, controller: controller);

      controller.openMode(AppMode.notes);
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(ModeMenu),
          matching: find.text(AppMode.notes.label),
        ),
        findsOneWidget,
      );
      // Notes is a built mode now, so the body is its surface rather than the
      // placeholder that used to carry the blurb.
      expect(find.byType(NotesSurface), findsOneWidget);
    });
  });

  group('touch targets', () {
    testWidgets('the trigger clears the minimum on both layouts',
        (tester) async {
      for (final (logical, platform) in [_phone, _desktop]) {
        await _pumpAt(tester, logical: logical, platform: platform);

        final targets = find.descendant(
          of: find.byType(ModeMenu),
          matching: find.byType(InkWell),
        );
        expect(targets, findsWidgets,
            reason: 'a tap-target test that finds no targets proves nothing');

        final size = tester.getSize(targets.first);
        expect(size.height, greaterThanOrEqualTo(kMinTouchTarget),
            reason: 'the trigger on $platform is ${size.height} tall');
        expect(size.width, greaterThanOrEqualTo(kMinTouchTarget),
            reason: 'the trigger on $platform is ${size.width} wide');
      }
    });

    testWidgets('so does the drawer button', (tester) async {
      // It did not. It measured 40 — an `IconButton` left to its own minimum —
      // and nothing had ever looked, because the sweep above followed the mode
      // control and stopped there. Found only because the ghost opposite it
      // failed the same check on its first run.
      await _pumpAt(tester, logical: _phone.$1, platform: _phone.$2);

      final button = find.byTooltip('Conversations');
      expect(button, findsOneWidget);

      final size = tester.getSize(button);
      expect(size.height, greaterThanOrEqualTo(kMinTouchTarget),
          reason: 'the drawer button is ${size.height} tall');
      expect(size.width, greaterThanOrEqualTo(kMinTouchTarget),
          reason: 'the drawer button is ${size.width} wide');
    });

    testWidgets('every entry in the open menu clears it too', (tester) async {
      // This has caught the mode controls twice — once at 40pt, once at 22pt
      // after an unrelated layout change — so it follows them into the menu
      // rather than staying on the control that used to exist.
      await _pumpAt(tester, logical: _phone.$1, platform: _phone.$2);
      await _openMenu(tester);

      final entries = find.byType(MenuItemButton);
      expect(entries, findsNWidgets(AppMode.values.length));

      for (var i = 0; i < entries.evaluate().length; i++) {
        final size = tester.getSize(entries.at(i));
        expect(size.height, greaterThanOrEqualTo(kMinTouchTarget),
            reason: 'entry $i is ${size.height} tall');
        expect(size.width, greaterThanOrEqualTo(kMinTouchTarget),
            reason: 'entry $i is ${size.width} wide');
      }
    });

    testWidgets('the menu fits on the narrowest phone', (tester) async {
      // The failure the pills had, in its new form: a menu wider than the
      // screen would clip its own entries. 320 is the narrowest target worth
      // supporting, and an iPad in a narrow split view lands here too.
      await _pumpAt(tester,
          logical: const Size(320, 700), platform: TargetPlatform.iOS);
      await _openMenu(tester);

      for (var i = 0; i < AppMode.values.length; i++) {
        final entry = find.byType(MenuItemButton).at(i);
        expect(tester.getTopLeft(entry).dx, greaterThanOrEqualTo(0),
            reason: 'entry $i starts off the left edge');
        expect(tester.getBottomRight(entry).dx, lessThanOrEqualTo(320),
            reason: 'entry $i runs past the right edge');
      }
    });
  });

  group('themes', () {
    testWidgets('both themes render the shell', (tester) async {
      // Not a screenshot comparison — proof that neither theme is missing a
      // token and throwing on lookup, which is the failure mode when a palette
      // gains a field and one side is not updated.
      for (final brightness in Brightness.values) {
        await _pumpAt(
          tester,
          logical: _desktop.$1,
          platform: _desktop.$2,
          brightness: brightness,
        );
        expect(find.byType(AppShell), findsOneWidget, reason: '$brightness');
      }
    });
  });
}
