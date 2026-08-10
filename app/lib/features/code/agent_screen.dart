import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/metrics.dart';
import '../../core/design/palette.dart';
import '../../data/agent.dart';
import '../../data/agent_store.dart';
import 'agent_runner.dart';
import 'changes_card.dart';
import 'code_chrome.dart';
import 'code_composer.dart';
import 'run_entry_view.dart';

/// One agent: what it was asked, what it did, and what it changed.
///
/// The screen the whole mode exists to reach. Everything before it is a way of
/// finding this.
class AgentScreen extends StatelessWidget {
  final String agentId;

  const AgentScreen({super.key, required this.agentId});

  @override
  Widget build(BuildContext context) {
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
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(
                          Space.lg, Space.sm, Space.lg, Space.md),
                      children: [
                        for (final entry in run.entries)
                          RunEntryView(entry: entry),
                        ChangesCard(paths: run.changedPaths),
                      ],
                    ),
            ),
            _Actions(agent: agent, running: running, runner: runner),
            CodeComposer(
              hint: 'Follow up…',
              onSend: running ? null : (text) => runner.send(agent, text),
            ),
          ],
        ),
      ),
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
