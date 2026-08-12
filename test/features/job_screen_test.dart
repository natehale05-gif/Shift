import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shift/agents/agent_loop.dart';
import 'package:shift/core/design/theme.dart';
import 'package:shift/data/agent.dart';
import 'package:shift/data/agent_run.dart';
import 'package:shift/data/agent_run_store.dart';
import 'package:shift/data/kv_store.dart';
import 'package:shift/features/work/job_screen.dart';
import 'package:shift/features/work/task_list.dart';
import 'package:shift/features/work/work_runner.dart';

/// A job you come back to: the plan at the top, the story underneath.
void main() {
  late Directory dir;
  late KvStore kv;
  late WorkAgents folders;
  late AgentRunStore runs;
  late WorkRunner runner;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('shift-job');
    File('${dir.path}/brief.md').writeAsStringSync('# Q3 brief\n');

    kv = KvStore(path: '${dir.path}/kv.json');
    await kv.load();
    folders = WorkAgents(kv);
    runs = AgentRunStore(kv, namespace: 'work');
    runner = WorkRunner(agents: folders, runs: runs);

    await folders.addWorkspace(
      LocalFolder(id: 'f1', name: 'documents', path: dir.path),
    );
    await folders.save(Agent(
      id: 'j1',
      title: 'Summary of the Q3 notes',
      workspaceId: 'f1',
      status: AgentStatus.needsAttention,
      updatedAt: DateTime(2026, 8, 10),
    ));
  });
  tearDown(() async {
    runner.dispose();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  /// Seeds the transcript **inside `runAsync`**, because a real-disk future
  /// created in a widget test's fake zone never completes — the write hangs
  /// rather than failing, which looks like the screen being slow.
  Future<void> writeRun(WidgetTester t, List<RunEntry> entries) => t.runAsync(
      () => runs.write(AgentRun(agentId: 'j1', entries: entries)));

  Future<void> pump(WidgetTester t) async {
    t.view.devicePixelRatio = 1.0;
    t.view.physicalSize = const Size(393, 852);
    addTearDown(t.view.reset);

    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: folders),
        ChangeNotifierProvider.value(value: runner),
      ],
      child: MaterialApp(
        theme: shiftTheme(Brightness.light, TargetPlatform.iOS),
        home: const JobScreen(jobId: 'j1'),
      ),
    ));
    await t.pump();
  }

  testWidgets('the current plan is pinned once, not printed twice', (t) async {
    // Found by looking at the running app: the pinned header and the
    // transcript both drew the latest plan, which reads as a rendering fault.
    await writeRun(t, [
      const RunAsked('summarise the Q3 notes'),
      const RunPlan([AgentTask('Read the notes'), AgentTask('Draft it')]),
    ]);
    await pump(t);

    expect(find.byType(TaskList), findsOneWidget);
    expect(find.text('Read the notes'), findsOneWidget);
  });

  testWidgets('an earlier plan stays in the transcript', (t) async {
    // The control, and the reason the fix skips only the *last* one: the plan
    // growing is something that happened, and only the transcript shows when.
    await writeRun(t, [
      const RunAsked('summarise the Q3 notes'),
      const RunPlan([AgentTask('Read the notes')]),
      const RunSaid('There are three files, not one.'),
      const RunPlan([AgentTask('Read the notes'), AgentTask('Read the rest')]),
    ]);
    await pump(t);

    // Twice: once in the old plan in the transcript, once in the pinned one.
    expect(find.text('Read the notes'), findsNWidgets(2));
    expect(find.text('Read the rest'), findsOneWidget);
  });

  testWidgets('a question it stopped on is shown, and the files it wrote',
      (t) async {
    await writeRun(t, [
      const RunAsked('summarise the Q3 notes'),
      RunTool(tool: 'write_file', input: const {'path': 'brief.md'})
        ..result = 'Wrote brief.md.'
        ..changedPath = 'brief.md',
      const RunQuestion('Which quarter should it cover?'),
      const RunEnded(),
    ]);
    await pump(t);

    expect(find.text('Which quarter should it cover?'), findsOneWidget);
    expect(find.text('Files'), findsOneWidget);
    expect(find.text('brief.md'), findsWidgets);
  });
}
