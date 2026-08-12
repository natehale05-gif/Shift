import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/metrics.dart';
import '../../core/design/palette.dart';
import '../../core/widgets/agent_composer.dart';
import '../../data/agent.dart';
import '../../data/agent_run.dart';
import '../code/run_changes.dart';
import '../code/run_entry_view.dart';
import 'approval_card.dart';
import 'produced_files.dart';
import 'task_list.dart';
import 'work_runner.dart';

/// One job: the plan at the top, what it has done in the middle, and whatever
/// it is waiting on just above the composer.
///
/// The vertical order is the argument. A person coming back to a job that has
/// been running reads it top-down and the first thing they need is *how far it
/// got*, not the last tool call.
class JobScreen extends StatefulWidget {
  final String jobId;

  const JobScreen({super.key, required this.jobId});

  @override
  State<JobScreen> createState() => _JobScreenState();
}

class _JobScreenState extends State<JobScreen> {
  @override
  void initState() {
    super.initState();
    // After the first frame, so the transcript paints immediately and the
    // diffs arrive a moment later rather than holding the screen blank on a
    // disk read.
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  void _refresh() {
    final job = context.read<WorkAgents>().agent(widget.jobId);
    if (job != null) context.read<WorkRunner>().refreshChanges(job);
  }

  @override
  Widget build(BuildContext context) {
    final jobId = widget.jobId;
    final c = context.colors;
    final folders = context.watch<WorkAgents>();
    final runner = context.watch<WorkRunner>();
    final job = folders.agent(jobId);

    if (job == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Job')),
        body: const Center(child: Text('This job is gone.')),
      );
    }

    final run = runner.runFor(jobId);
    final running = runner.isRunning(jobId);
    final pending = runner.approvalFor(jobId);

    return Scaffold(
      backgroundColor: c.ground,
      appBar: AppBar(title: Text(job.title)),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            TaskList(tasks: TaskList.latestIn(run)),
            Expanded(
              child: run.entries.isEmpty
                  ? const Center(child: Text('Nothing yet.'))
                  : _Transcript(
                      job: job,
                      run: run,
                      changes: runner.changesOf(jobId),
                      runner: runner,
                    ),
            ),
            if (pending != null)
              ApprovalCard(
                question: pending,
                onAllow: () => runner.answerApproval(jobId, true),
                onDeny: () => runner.answerApproval(jobId, false),
              ),
            if (running)
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.xs),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: () => runner.stop(jobId),
                      child: const Text('Stop'),
                    ),
                  ],
                ),
              ),
            AgentComposer(
              hint: 'Follow up…',
              onSend: running ? null : (text) => runner.send(job, text),
            ),
          ],
        ),
      ),
    );
  }
}

/// What it did, with each edit's diff under it, and the files at the end.
class _Transcript extends StatelessWidget {
  final Agent job;
  final AgentRun run;
  final List<FileChange> changes;
  final WorkRunner runner;

  const _Transcript({
    required this.job,
    required this.run,
    required this.changes,
    required this.runner,
  });

  @override
  Widget build(BuildContext context) {
    final byPath = {for (final c in changes) c.path: c};

    // The diff goes under the **last** row that touched each file. The
    // baseline is captured once per run rather than once per edit, so what
    // exists is the file's whole change — printing it under all three of three
    // edits would say each edit did all of it.
    final showAt = <int, FileChange>{};
    for (final path in byPath.keys) {
      for (var i = run.entries.length - 1; i >= 0; i--) {
        final entry = run.entries[i];
        if (entry is RunTool && entry.changedPath == path) {
          showAt[i] = byPath[path]!;
          break;
        }
      }
    }

    // The current plan is pinned above this list, so printing it again here
    // reads as a rendering fault rather than as history. *Earlier* versions
    // stay: the third task appearing halfway through is the job telling you
    // what it found, and that is only visible in place.
    final pinned = run.entries.lastIndexWhere((e) => e is RunPlan);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          Space.lg, Space.sm, Space.lg, AgentComposer.reservedHeight),
      children: [
        for (var i = 0; i < run.entries.length; i++)
          if (i != pinned)
            RunEntryView(entry: run.entries[i], change: showAt[i]),
        ProducedFiles(
          paths: run.changedPaths,
          workspace: runner.workspaceFor(job).workspace,
        ),
      ],
    );
  }
}
