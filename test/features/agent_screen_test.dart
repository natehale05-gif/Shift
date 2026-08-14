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
import 'package:shift/features/code/agent_screen.dart';
import 'package:shift/features/code/changes_card.dart';
import 'package:shift/features/code/run_entry_view.dart';

/// The screen the whole mode exists to reach.
void main() {
  late Directory dir;
  late KvStore kv;
  late AgentStore agents;
  late AgentRunStore runs;
  late AgentRunner runner;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('shift-screen');
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
      title: 'Rename the greeting',
      workspaceId: 'w1',
      status: AgentStatus.needsAttention,
      updatedAt: DateTime.now(),
    ));
  });
  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  /// Seeds a transcript and, when the entries claim to have changed files, the
  /// files themselves.
  ///
  /// The Changes card reads the real workspace now, so a transcript naming a
  /// path that is not on disk produces no diff — correctly. Fixtures that
  /// declared changes without making any were passing for the wrong reason.
  Future<void> pump(
    WidgetTester tester, {
    List<RunEntry> entries = const [],
    Map<String, (String before, String after)> files = const {},
  }) async {
    // Real disk inside `testWidgets` deadlocks against the fake async clock
    // unless it is run outside it. This has cost this suite two hangs.
    await tester.runAsync(() async {
      final run = AgentRun(
        agentId: 'a1',
        entries: [...entries],
        baseline: {for (final e in files.entries) e.key: e.value.$1},
      );
      await runs.write(run);
      await runs.writeBaseline(run);
      for (final entry in files.entries) {
        final file = File('${dir.path}/${entry.key}');
        await file.parent.create(recursive: true);
        await file.writeAsString(entry.value.$2);
      }
    });

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: agents),
        ChangeNotifierProvider.value(value: runner),
      ],
      child: MaterialApp(
        theme: shiftTheme(Brightness.dark, TargetPlatform.iOS)
            .copyWith(extensions: const [ShiftColors.code]),
        home: const AgentScreen(agentId: 'a1'),
      ),
    ));
    await tester.pump();
  }

  /// Reads the diffs the way the screen does, then rebuilds.
  ///
  /// The read has to happen in [WidgetTester.runAsync] because it is real
  /// `dart:io`, which the test clock never advances — a future started inside a
  /// `build` would sit unresolved for the whole test and the card would render
  /// as permanently empty. Asking the runner directly is also closer to the
  /// truth: the runner owns the answer, and both screens only read it.
  Future<void> settleDisk(WidgetTester tester) async {
    await tester.runAsync(
        () => runner.refreshChanges(agents.agent('a1')!));
    await tester.pump();
  }

  testWidgets('the title is the agent, and the transcript is what it did',
      (tester) async {
    await pump(tester, entries: [
      const RunAsked('rename the greeting'),
      const RunSaid('Reading it first.'),
      RunTool(tool: 'edit_file', input: const {'path': 'lib/greeting.dart'})
        ..result = 'Edited lib/greeting.dart.'
        ..changedPath = 'lib/greeting.dart',
    ], files: {
      'lib/greeting.dart': ("const hello = 'hi';\n", "const hello = 'hey';\n"),
    });
    await settleDisk(tester);

    expect(find.text('Rename the greeting'), findsOneWidget);
    expect(find.text('rename the greeting'), findsOneWidget);
    expect(find.text('Reading it first.'), findsOneWidget);
    expect(find.text('edit_file'), findsOneWidget);
    // The subject, not the serialised arguments — on the tool's own line, and
    // again in the summary of what changed.
    expect(find.text('lib/greeting.dart'), findsNWidgets(2));
  });

  testWidgets('a run that changed nothing shows no Changes card',
      (tester) async {
    // A card reading "Changes 0" is a heading over an absence.
    await pump(tester, entries: [
      const RunAsked('what is in here'),
      RunTool(tool: 'glob', input: const {'pattern': '**'})..result = 'a.dart',
    ]);

    // `find.text` does not see a `Text.rich`, so the heading is looked for the
    // way it is actually built — an assertion that cannot fail is worse than
    // no assertion, and this one could not.
    expect(find.textContaining('Changes'), findsNothing);
    expect(tester.getSize(find.byType(ChangesCard)).height, 0);
  });

  testWidgets('the files it touched are listed with what it did to each',
      (tester) async {
    await pump(tester, entries: [
      RunTool(tool: 'write_file', input: const {})..changedPath = 'a.dart',
      RunTool(tool: 'edit_file', input: const {})..changedPath = 'a.dart',
      RunTool(tool: 'edit_file', input: const {})..changedPath = 'b.dart',
    ], files: {
      'a.dart': ('one\n', 'ONE\ntwo\n'),
      'b.dart': ('keep\n', 'keep\n'),
    });
    await settleDisk(tester);

    expect(find.textContaining('Changes'), findsOneWidget);
    // Only `a.dart`: `b.dart` is identical to its baseline, so it is not a
    // changed file however many tools touched it.
    expect(find.textContaining('  1'), findsOneWidget);
    expect(find.text('a.dart'), findsOneWidget);
    expect(find.text('+2 -1'), findsWidgets);
    expect(find.text('b.dart'), findsNothing);
  });

  testWidgets('a failure is shown with the fact behind it', (tester) async {
    await pump(tester, entries: [
      const RunAsked('do the thing'),
      const RunEnded(
        reason: 'That key was rejected.',
        detail: 'HTTP 401 from api.anthropic.com',
      ),
    ]);

    expect(find.text('That key was rejected.'), findsOneWidget);
    expect(find.text('HTTP 401 from api.anthropic.com'), findsOneWidget);
  });

  testWidgets('a clean ending says nothing', (tester) async {
    // The transcript ending is the ending. A banner announcing that nothing
    // went wrong would be on every successful run.
    await pump(tester, entries: [
      const RunSaid('Changed the greeting.'),
      const RunEnded(),
    ]);

    expect(find.text('Changed the greeting.'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
  });

  testWidgets('every control clears the minimum touch target', (tester) async {
    await pump(tester, entries: [
      for (var i = 0; i < 8; i++)
        RunTool(tool: 'read_file', input: {'path': 'f$i.dart'})
          ..result = 'x'
          ..changedPath = 'f$i.dart',
    ]);

    // Scoped to this screen's own rows. A blanket sweep of every `InkWell`
    // also catches the framework's internals — and the visible circle inside a
    // deliberately larger touch area, which is the pattern, not a defect.
    final rows = find.byType(RunEntryView);
    for (var i = 0; i < rows.evaluate().length; i++) {
      expect(tester.getSize(rows.at(i)).height,
          greaterThanOrEqualTo(kMinTouchTarget),
          reason: 'transcript row $i');
    }
  });
}
