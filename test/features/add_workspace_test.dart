import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shift/core/design/metrics.dart';
import 'package:shift/core/design/palette.dart';
import 'package:shift/core/design/theme.dart';
import 'package:shift/data/agent_store.dart';
import 'package:shift/data/kv_store.dart';
import 'package:shift/features/code/add_workspace_sheet.dart';

/// The sheet that makes the mode reachable at all.
void main() {
  late Directory dir;
  late AgentStore agents;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('shift-add-ws');
    final kv = KvStore(path: '${dir.path}/kv.json');
    await kv.load();
    agents = AgentStore(kv);
  });
  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  /// Runs [body] as if this were [platform].
  ///
  /// Reset in a `finally` rather than through `addTearDown`: the framework
  /// asserts that no foundation debug variable is still set when the test body
  /// ends, and a teardown runs after that check.
  Future<void> asPlatform(
      TargetPlatform platform, Future<void> Function() body) async {
    debugDefaultTargetPlatformOverride = platform;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  Future<void> pump(WidgetTester tester, TargetPlatform platform) async {
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: agents,
      child: MaterialApp(
        theme: shiftTheme(Brightness.dark, platform)
            .copyWith(
              platform: platform,
              extensions: const [ShiftColors.code],
            ),
        home: const Scaffold(body: AddWorkspaceSheet()),
      ),
    ));
    await tester.pump();
  }

  testWidgets('on a desktop the folder source is offered', (tester) async {
    await asPlatform(TargetPlatform.linux, () async {
      await pump(tester, TargetPlatform.linux);
      expect(canPickFolder, isTrue);
      expect(find.text('The agent reads and edits it directly'),
          findsOneWidget);
    });
  });

  testWidgets('on a phone it says why the folder is not on offer', (tester) async {
    await asPlatform(TargetPlatform.iOS, () async {
      // A control that fails when pressed is worse than one that explains
      // itself — there is genuinely no folder here to point at.
      await pump(tester, TargetPlatform.iOS);
      expect(canPickFolder, isFalse);
      expect(find.textContaining('Only on the desktop app'), findsOneWidget);
    });
  });

  testWidgets('GitHub is listed and says it is not ready', (tester) async {
    await asPlatform(TargetPlatform.linux, () async {
      // Listed rather than hidden: knowing it is coming is worth more than a
      // shorter sheet, and one row reads like something is broken.
      await pump(tester, TargetPlatform.linux);
      expect(find.text('A GitHub repository'), findsOneWidget);
      expect(find.textContaining('not built yet'), findsOneWidget);
    });
  });

  testWidgets('every row clears the minimum touch target', (tester) async {
    await asPlatform(TargetPlatform.linux, () async {
      await pump(tester, TargetPlatform.linux);
      final rows = find.byType(InkWell);
      for (var i = 0; i < rows.evaluate().length; i++) {
        final size = tester.getSize(rows.at(i));
        if (size.isEmpty) continue;
        expect(size.height, greaterThanOrEqualTo(kMinTouchTarget),
            reason: 'source row $i');
      }
    });
  });
}
