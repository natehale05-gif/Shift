import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/metrics.dart';
import '../../core/design/palette.dart';
import '../../core/widgets/agent_composer.dart';
import '../../data/agent.dart';
import '../../data/agent_run.dart';
import '../../data/agent_store.dart';
import 'agent_runner.dart';
import 'changes_card.dart';
import 'code_chrome.dart';
import 'file_diff_screen.dart';
import 'run_changes.dart';
import 'run_entry_view.dart';

/// One agent: what it was asked, what it did, and what it changed.
///
/// The screen the whole mode exists to reach. Everything before it is a way of
/// finding this.
class AgentScreen extends StatefulWidget {
  final String agentId;

  const AgentScreen({super.key, required this.agentId});

  @override
  State<AgentScreen> createState() => _AgentScreenState();
}

class _AgentScreenState extends State<AgentScreen> {
  @override
  void initState() {
    super.initState();
    // After the first frame, so the transcript paints immediately and its
    // diffs arrive a moment later rather than holding the screen blank on a
    // disk read.
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  void _refresh() {
    final agent = context.read<AgentStore>().agent(widget.agentId);
    if (agent != null) context.read<AgentRunner>().refreshChanges(agent);
  }

  @override
  Widget build(BuildContext context) {
    final agentId = widget.agentId;
    final c = context.colors;
    final agents = context.watch<AgentStore>();
    final runner = context.watch<AgentRunner>();
    final agent = agents.agent(agentId);

    if (agent == null) {
      return Scaffold(
        backgroundColor: c.ground,
        body: SafeArea(
          child: Column(
            children: [
              const CodeDetailHeader(title: 'Agent'),
              const Expanded(
                child: CodeEmpty(
                  title: 'This agent is gone',
                  detail: 'It was removed, or its workspace was',
                ),
              ),
            ],
          ),
        ),
      );
    }

    final run = runner.runFor(agentId);
    final running = runner.isRunning(agentId);

    return Scaffold(
      backgroundColor: c.ground,
      body: SafeArea(
        child: Column(
          children: [
            CodeDetailHeader(title: agent.title),
            Expanded(
              child: run.entries.isEmpty
                  ? const CodeEmpty(
                      title: 'Nothing yet',
                      detail: 'Tell it what to do below',
                    )
                  : _Transcript(
                      agent: agent,
                      run: run,
                      changes: runner.changesOf(agentId),
                    ),
            ),
            _Actions(agent: agent, running: running, runner: runner),
            AgentComposer(
              hint: 'Follow up…',
              onSend: running ? null : (text) => runner.send(agent, text),
            ),
          ],
        ),
      ),
    );
  }
}

/// The transcript, with each edit's diff under it.
class _Transcript extends StatelessWidget {
  final Agent agent;
  final AgentRun run;
  final List<FileChange> changes;

  const _Transcript({
    required this.agent,
    required this.run,
    required this.changes,
  });

  @override
  Widget build(BuildContext context) {
    final byPath = {for (final c in changes) c.path: c};

    // Which row carries the diff: the last one that touched each path. The
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

    return ListView(
      padding:
          const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.md),
      children: [
        for (var i = 0; i < run.entries.length; i++)
          RunEntryView(entry: run.entries[i], change: showAt[i]),
        ChangesCard(
          changes: changes,
          onOpen: (path) => Navigator.of(context).push(
            codeRoute((_) => FileDiffScreen(agentId: agent.id, path: path)),
          ),
        ),
      ],
    );
  }
}

/// The row of pills above the composer.
///
/// Only what can actually be done right now. A "View PR Draft" pill on a run
/// with nothing to push is a control that has to explain itself when tapped,
/// which is worse than not being there.
class _Actions extends StatelessWidget {
  final Agent agent;
  final bool running;
  final AgentRunner runner;

  const _Actions({
    required this.agent,
    required this.running,
    required this.runner,
  });

  @override
  Widget build(BuildContext context) {
    if (!running) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.xs),
      child: Row(
        children: [
          _Pill(label: 'Stop', onTap: () => runner.stop(agent.id)),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _Pill({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Material(
      color: c.surfaceRaised,
      borderRadius: BorderRadius.circular(Radii.pill),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: kMinTouchTarget),
          padding: const EdgeInsets.symmetric(horizontal: Space.lg),
          alignment: Alignment.center,
          child: Text(
            label,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: c.text),
          ),
        ),
      ),
    );
  }
}
