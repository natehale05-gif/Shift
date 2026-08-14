import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shift/core/design/metrics.dart';
import 'package:shift/core/design/palette.dart';
import 'package:shift/core/design/theme.dart';
import 'package:shift/data/agent.dart';
import 'package:shift/data/agent_run.dart';
import 'package:shift/data/agent_run_store.dart';
import 'package:shift/data/agent_store.dart';
import 'package:shift/data/kv_store.dart';
import 'package:shift/features/code/agent_runner.dart';
import 'package:shift/features/code/file_diff_screen.dart';
import 'package:shift/features/code/hunk_view.dart';

/// The review screen, against real files.
///
/// Reverting writes to disk, so the assertions read the file back rather than
/// asking the widget what it thinks — the app's view of a file is not evidence
/// about the file.
void main() {
  late Directory dir;
  late KvStore kv;
  late AgentStore agents;
  late AgentRunStore runs;
  late AgentRunner runner;

  // Far enough apart to stay two hunks: changes closer than twice the context
  // are deliberately merged, and a seven-line file cannot hold two.
  final lines = [for (var i = 0; i < 20; i++) 'line $i'];
  final before = '${lines.join('\n')}\n';
  final after = before
      .replaceFirst('line 1\n', 'LINE 1\n')
      .replaceFirst('line 18\n', 'LINE 18\n');

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('shift-diff-screen');
    kv = KvStore(path: '${dir.path}/kv.json');
    await kv.load();
    agents = AgentStore(kv);
    runs = AgentRunStore(kv);
    runner = AgentRunner(agents: agents, runs: runs);

    await agents.addWorkspace(
      LocalFolder(id: 'w1', name: 'repo', path: dir.path),
    );
    await agents.save(Agent(
      id: 'a1',
      title: 'Shout at both ends',
      workspaceId: 'w1',
      status: AgentStatus.needsAttention,
      updatedAt: DateTime.now(),
    ));

    final run = AgentRun(
      agentId: 'a1',
      entries: [
        RunTool(tool: 'write_file', input: const {'path': 'f.txt'})
          ..result = 'Wrote f.txt.'
          ..changedPath = 'f.txt',
      ],
      baseline: {'f.txt': before},
    );
    await runs.write(run);
    await runs.writeBaseline(run);
    File('${dir.path}/f.txt').writeAsStringSync(after);
  });
  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  String onDisk() => File('${dir.path}/f.txt').readAsStringSync();

  Future<void> pump(WidgetTester tester) async {
    // Real `dart:io`, which the test clock never advances — so the read has to
    // happen in `runAsync` rather than inside a build.
    await tester.runAsync(() => runner.refreshChanges(agents.agent('a1')!));

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: agents),
        ChangeNotifierProvider.value(value: runner),
      ],
      child: MaterialApp(
        theme: shiftTheme(Brightness.dark, TargetPlatform.iOS)
            .copyWith(extensions: const [ShiftColors.code]),
        home: const FileDiffScreen(agentId: 'a1', path: 'f.txt'),
      ),
    ));
    await tester.pump();
  }

  /// Taps [finder] and lets the write and the re-read land.
  ///
  /// Tapped **inside** `runAsync`, so the handler's `dart:io` futures are
  /// created in the real zone. Started in the fake one they never resolve, and
  /// the button silently appears to do nothing — which is exactly what a
  /// broken Revert would look like, so the distinction matters.
  ///
  /// The wait is a poll rather than a fixed delay. A fixed one is a bet on how
  /// long a disk takes, and it is a bet this file lost the moment the suite got
  /// wide enough to run several file-touching tests at once: the write had
  /// landed, the re-read had not, and the screen still showed the hunk that was
  /// gone from the file. Waiting for the *condition* cannot flake that way.
  Future<void> tapAndSettle(
    WidgetTester tester,
    Finder finder, {
    required bool Function() until,
  }) async {
    await tester.runAsync(() async {
      await tester.tap(finder);
      for (var i = 0; i < 200; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
        if (until()) return;
      }
    });
    await tester.pump();
  }

  testWidgets('it shows the path, the count, and a hunk per change',
      (tester) async {
    await pump(tester);

    expect(find.text('f.txt'), findsOneWidget);
    expect(find.text('+2 -2'), findsOneWidget);
    expect(find.byType(HunkView), findsNWidgets(2));
    // The marker column, so a diff is readable without relying on colour.
    expect(find.text('- line 1'), findsOneWidget);
    expect(find.text('+ LINE 1'), findsOneWidget);
  });

  testWidgets('reverting one hunk changes the file and leaves the other',
      (tester) async {
    await pump(tester);
    await tapAndSettle(tester, find.text('Revert').first,
        until: () => find.byType(HunkView).evaluate().length == 1);

    expect(onDisk(), contains('line 1\n'));
    expect(onDisk(), contains('LINE 18'));
    expect(find.byType(HunkView), findsOneWidget,
        reason: 'the reverted hunk is no longer a change');
  });

  testWidgets('reverting all restores the file and the screen says so',
      (tester) async {
    await pump(tester);
    await tapAndSettle(tester, find.text('Revert all'),
        until: () => find.byType(HunkView).evaluate().isEmpty);

    expect(onDisk(), before);
    // Not an error state: this is what success looks like here.
    expect(find.text('Nothing changed here'), findsOneWidget);
    expect(find.byType(HunkView), findsNothing);
  });

  testWidgets('a file already matching its baseline shows nothing to review',
      (tester) async {
    File('${dir.path}/f.txt').writeAsStringSync(before);
    await pump(tester);

    expect(find.text('Nothing changed here'), findsOneWidget);
  });

  testWidgets('every control clears the minimum touch target', (tester) async {
    await pump(tester);

    for (final label in ['Revert', 'Revert all']) {
      final finder = find.ancestor(
        of: find.text(label),
        matching: find.byType(InkWell),
      );
      for (var i = 0; i < finder.evaluate().length; i++) {
        expect(tester.getSize(finder.at(i)).height,
            greaterThanOrEqualTo(kMinTouchTarget),
            reason: '$label $i');
      }
    }
  });
}
