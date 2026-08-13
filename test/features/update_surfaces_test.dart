import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shift/core/design/metrics.dart';
import 'package:shift/core/design/theme.dart';
import 'package:shift/core/update/update_check.dart';
import 'package:shift/data/kv_store.dart';
import 'package:shift/data/update_store.dart';
import 'package:shift/features/settings/update_card.dart';
import 'package:shift/shell/update_banner.dart';

/// The two places an update is read: a card in Settings and a strip above the
/// shell.
///
/// Both are off-web only, and that is asserted rather than assumed — this
/// build registers no service worker, so a browser reload is already the newest
/// deploy and a card offering to download an installer into a tab would be
/// offering something meaningless.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('shift_update_ui');
    PackageInfo.setMockInitialValues(
      appName: 'SHIFT AI',
      packageName: 'club.shiftai.shift',
      version: '0.2.0',
      buildNumber: '2',
      buildSignature: '',
    );
  });
  tearDown(() => dir.deleteSync(recursive: true));

  /// Built inside [WidgetTester.runAsync], and that is not incidental.
  ///
  /// `testWidgets` runs its body in a fake-async zone where timers do not fire
  /// on their own, so an `await` on **real** file I/O — which `KvStore.load`
  /// does — never completes and the test simply hangs with no output. The
  /// store test next door is a plain `test()` and does not hit this.
  Future<UpdateStore> storeWith(WidgetTester t,
      {String tag = 'v0.2.1', bool check = false}) async {
    final client = MockClient((_) async => http.Response(
          jsonEncode({
            'tag_name': tag,
            'html_url': 'https://example.test/releases/tag/$tag',
            'assets': const [],
          }),
          200,
        ));
    final store = UpdateStore(
      KvStore(path: '${dir.path}/kv.json'),
      check: UpdateCheck(clientFactory: () => client),
    );
    await t.runAsync(() async {
      await store.load();
      if (check) await store.checkNow();
    });
    return store;
  }

  Widget host(UpdateStore store, Widget child) =>
      ChangeNotifierProvider.value(
        value: store,
        child: MaterialApp(
          theme: shiftTheme(Brightness.light, TargetPlatform.iOS),
          home: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      );

  testWidgets('the card shows the running version', (t) async {
    final store = await storeWith(t);
    await t.pumpWidget(host(store, const UpdateCard()));
    await t.pumpAndSettle();

    expect(find.text('SHIFT AI 0.2.0'), findsOneWidget);
    expect(find.text('Updates'), findsOneWidget);
  });

  testWidgets('a newer release is named, and the strip appears', (t) async {
    final store = await storeWith(t, tag: 'v0.2.1', check: true);

    await t.pumpWidget(host(store, const UpdateBanner()));
    await t.pumpAndSettle();

    expect(find.textContaining('v0.2.1'), findsOneWidget);
  });

  testWidgets('the same version says so and shows no strip', (t) async {
    final store = await storeWith(t, tag: 'v0.2.0', check: true);

    await t.pumpWidget(host(store, const UpdateBanner()));
    await t.pumpAndSettle();
    expect(find.byType(TextButton), findsNothing);

    await t.pumpWidget(host(store, const UpdateCard()));
    await t.pumpAndSettle();
    expect(find.text("You're on the latest version."), findsOneWidget);
  });

  testWidgets('a check that could not run never claims to be current',
      (t) async {
    // The distinction the whole status enum exists for: "up to date" is a
    // finding, and an app that says it after failing to ask is lying.
    final client = MockClient((_) async => http.Response('nope', 404));
    final store = UpdateStore(
      KvStore(path: '${dir.path}/kv.json'),
      check: UpdateCheck(clientFactory: () => client),
    );
    await t.runAsync(() async {
      await store.load();
      await store.checkNow();
    });

    await t.pumpWidget(host(store, const UpdateCard()));
    await t.pumpAndSettle();

    expect(find.textContaining("Couldn't check"), findsOneWidget);
    expect(find.text("You're on the latest version."), findsNothing);
  });

  testWidgets('dismissing the strip leaves the card reporting it', (t) async {
    // Two different jobs: the strip interrupts, the card answers a question
    // somebody went looking for. Dismissing the first must not silence the
    // second.
    final store = await storeWith(t, tag: 'v0.2.1', check: true);
    await t.runAsync(store.dismiss);

    await t.pumpWidget(host(store, const UpdateBanner()));
    await t.pumpAndSettle();
    expect(find.textContaining('v0.2.1'), findsNothing);

    await t.pumpWidget(host(store, const UpdateCard()));
    await t.pumpAndSettle();
    expect(find.textContaining('v0.2.1'), findsOneWidget);
  });

  testWidgets('every control clears the tap minimum', (t) async {
    final store = await storeWith(t, tag: 'v0.2.1', check: true);

    await t.pumpWidget(host(store, const UpdateCard()));
    await t.pumpAndSettle();

    for (final label in ['Check now', 'Release notes']) {
      expect(t.getSize(find.widgetWithText(TextButton, label)).height,
          greaterThanOrEqualTo(kMinTouchTarget),
          reason: label);
    }
  });
}
