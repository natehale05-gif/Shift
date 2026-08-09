import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shift/core/design/metrics.dart';
import 'package:shift/core/design/theme.dart';
import 'package:shift/shell/app_shell.dart';
import 'package:shift/shell/mode.dart';
import 'package:shift/shell/mode_pills.dart';
import 'package:shift/shell/mode_rail.dart';
import 'package:shift/shell/shell_controller.dart';

Widget _app({
  required Brightness brightness,
  required TargetPlatform platform,
  ShellController? controller,
}) =>
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: controller ?? ShellController()),
      ],
      child: MaterialApp(
        // The platform travels through the theme rather than through
        // `debugDefaultTargetPlatformOverride`, because the shell reads
        // `Theme.of(context).platform` — and because the global is a foundation
        // debug variable the test framework asserts is unset by the time a test
        // body ends, which `addTearDown` is too late to satisfy.
        theme: shiftTheme(brightness).copyWith(platform: platform),
        home: const AppShell(),
      ),
    );

/// Drives the shell at a given window size and platform.
Future<void> _pumpAt(
  WidgetTester tester, {
  required Size logical,
  required TargetPlatform platform,
  Brightness brightness = Brightness.light,
  ShellController? controller,
}) async {
  // The window, which is what the shell reads. At a device pixel ratio of 1
  // the physical size and the logical size are the same number, which keeps
  // the cases below readable as the sizes people actually quote.
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = logical;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app(
      brightness: brightness, platform: platform, controller: controller));
  await tester.pumpAndSettle();
}

void main() {
  group('the shell picks its arrangement from the device', () {
    testWidgets('a phone gets pills, not a rail', (tester) async {
      await _pumpAt(tester,
          logical: const Size(393, 852), platform: TargetPlatform.iOS);

      expect(find.byType(ModePills), findsOneWidget);
      expect(find.byType(ModeRail), findsNothing);
    });

    testWidgets('an iPad gets the rail', (tester) async {
      await _pumpAt(tester,
          logical: const Size(1024, 1366), platform: TargetPlatform.iOS);

      expect(find.byType(ModeRail), findsOneWidget);
      expect(find.byType(ModePills), findsNothing);
    });

    testWidgets('an iPad in a narrow split view gets the phone surface',
        (tester) async {
      // A deliberate answer, not a fallback. A third of an iPad cannot host a
      // file tree, an editor and a terminal at once, so the task-first surface
      // is the better fit at that width — and it comes back the moment the
      // split is widened.
      await _pumpAt(tester,
          logical: const Size(320, 1366), platform: TargetPlatform.iOS);

      expect(find.byType(ModePills), findsOneWidget);
      expect(find.byType(ModeRail), findsNothing);
    });

    testWidgets('a narrow desktop window keeps the rail', (tester) async {
      // The regression that matters: this must not become a phone layout
      // because someone resized their window.
      await _pumpAt(tester,
          logical: const Size(420, 700), platform: TargetPlatform.macOS);

      expect(find.byType(ModeRail), findsOneWidget);
      expect(find.byType(ModePills), findsNothing);
    });
  });

  group('modes', () {
    testWidgets('every mode is reachable and opens its own surface',
        (tester) async {
      await _pumpAt(tester,
          logical: const Size(1280, 900), platform: TargetPlatform.linux);

      for (final mode in AppMode.values) {
        await tester.tap(find.text(mode.label).first);
        await tester.pumpAndSettle();

        // The blurb is unique per mode, so finding it proves the body
        // actually changed rather than the label merely highlighting.
        expect(find.text(mode.blurb), findsOneWidget, reason: mode.label);
      }
    });

    testWidgets('chat is where the app opens', (tester) async {
      // The default is a product decision — ask for anything, get it back —
      // so it is pinned rather than left to enum ordering.
      await _pumpAt(tester,
          logical: const Size(1280, 900), platform: TargetPlatform.linux);

      expect(find.text(AppMode.chat.blurb), findsOneWidget);
    });
  });

  group('the phone row keeps the active mode in sight', () {
    testWidgets('a mode selected from off-screen is scrolled into view',
        (tester) async {
      // Six labelled pills do not fit across a phone, so two are always off
      // the right edge. The mode can also be set from outside the row — a
      // Shortcut, Siri, a deep link — and arriving on a screen whose active
      // tab is scrolled out of sight reads as the app having ignored you.
      final controller = ShellController();
      addTearDown(controller.dispose);
      await _pumpAt(tester,
          logical: const Size(393, 852),
          platform: TargetPlatform.iOS,
          controller: controller);

      final width =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;

      // Scoped to the row: once Notes is open its name is also the heading of
      // the mode body, and an unscoped finder matches both.
      final pill = find.descendant(
        of: find.byType(ModePills),
        matching: find.text(AppMode.notes.label),
      );

      // Notes is last, so it starts off-screen. Proving that first means the
      // assertion afterwards cannot pass by accident.
      expect(tester.getCenter(pill).dx, greaterThan(width),
          reason: 'the last mode should start off-screen, or this proves nothing');

      controller.openMode(AppMode.notes);
      await tester.pumpAndSettle();

      final dx = tester.getCenter(pill).dx;
      expect(dx, greaterThanOrEqualTo(0));
      expect(dx, lessThanOrEqualTo(width));
    });
  });

  group('touch targets', () {
    testWidgets('every mode control clears the minimum, on both layouts',
        (tester) async {
      // Asserted rather than trusted, and asserted on both arrangements,
      // because the rail and the pills size themselves differently and only
      // one of them was designed on a phone.
      for (final (logical, platform) in [
        (const Size(393, 852), TargetPlatform.iOS),
        (const Size(1280, 900), TargetPlatform.linux),
      ]) {
        await _pumpAt(tester, logical: logical, platform: platform);

        final targets = find.byType(InkWell);
        expect(targets, findsWidgets,
            reason: 'a tap-target test that finds no targets proves nothing');

        for (var i = 0; i < targets.evaluate().length; i++) {
          final size = tester.getSize(targets.at(i));
          expect(size.height, greaterThanOrEqualTo(kMinTouchTarget),
              reason: 'control $i on $platform is ${size.height} tall');
          expect(size.width, greaterThanOrEqualTo(kMinTouchTarget),
              reason: 'control $i on $platform is ${size.width} wide');
        }
      }
    });
  });

  group('themes', () {
    testWidgets('both themes render the shell', (tester) async {
      // Not a screenshot comparison — just proof that neither theme is
      // missing a token and throwing on lookup, which is the failure mode
      // when a palette gains a field and one side is not updated.
      for (final brightness in Brightness.values) {
        await _pumpAt(
          tester,
          logical: const Size(1280, 900),
          platform: TargetPlatform.linux,
          brightness: brightness,
        );
        expect(find.byType(AppShell), findsOneWidget, reason: '$brightness');
      }
    });
  });
}
