import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/metrics.dart';
import '../../core/design/palette.dart';
import '../../data/agent_store.dart';
import 'agent_runner.dart';
import 'code_chrome.dart';
import 'hunk_view.dart';
import 'run_changes.dart';

/// One file, and what the run did to it.
///
/// **Revert is the only action, and that is not a shortcut.** The agent has
/// already written these files — that is how this app works, and the decision
/// the user made when they asked for it to work the way Claude Code does. So
/// "accept" is doing nothing, and an Accept button beside a Revert button would
/// be a control that does nothing sitting next to one that does something,
/// which teaches people that neither can be trusted.
class FileDiffScreen extends StatefulWidget {
  final String agentId;
  final String path;

  const FileDiffScreen({
    super.key,
    required this.agentId,
    required this.path,
  });

  @override
  State<FileDiffScreen> createState() => _FileDiffScreenState();
}

class _FileDiffScreenState extends State<FileDiffScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  /// The runner holds the answer, so a revert here is visible in the
  /// transcript behind this screen without either of them telling the other.
  void _refresh() {
    final agent = context.read<AgentStore>().agent(widget.agentId);
    if (agent != null) context.read<AgentRunner>().refreshChanges(agent);
  }

  Future<void> _revert(FileChange change, {int? index}) async {
    final runner = context.read<AgentRunner>();
    final agent = context.read<AgentStore>().agent(widget.agentId);
    if (agent == null) return;

    final workspace = runner.workspaceFor(agent).workspace;
    final baseline = runner.runFor(widget.agentId).baseline[change.path] ?? '';
    if (workspace == null) return;

    if (index == null) {
      await revertFile(
          workspace: workspace, change: change, baseline: baseline);
    } else {
      await revertHunk(
          workspace: workspace,
          change: change,
          baseline: baseline,
          index: index);
    }
    await runner.refreshChanges(agent);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final runner = context.watch<AgentRunner>();

    FileChange? change;
    for (final candidate in runner.changesOf(widget.agentId)) {
      if (candidate.path == widget.path) change = candidate;
    }

    return Scaffold(
      backgroundColor: c.ground,
      body: SafeArea(
        child: Column(
          children: [
            CodeDetailHeader(title: widget.path),
            Expanded(
              child: change == null
                  // Not an error, and the commonest way to arrive here is by
                  // reverting everything — a success whose result is that there
                  // is nothing left to show.
                  ? const CodeEmpty(
                      title: 'Nothing changed here',
                      detail: 'This file matches what it was before the run',
                    )
                  : _Hunks(change: change, onRevert: _revert),
            ),
          ],
        ),
      ),
    );
  }
}

class _Hunks extends StatelessWidget {
  final FileChange change;
  final Future<void> Function(FileChange, {int? index}) onRevert;

  const _Hunks({required this.change, required this.onRevert});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.xl),
      children: [
        Row(
          children: [
            Text('${change.stat}',
                style: text.bodyMedium?.copyWith(color: c.textMuted)),
            const Spacer(),
            _Revert(
              label: 'Revert all',
              onTap: () => onRevert(change),
            ),
          ],
        ),
        for (var i = 0; i < change.hunks.length; i++)
          Padding(
            padding: const EdgeInsets.only(top: Space.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                HunkView(hunk: change.hunks[i]),
                // A `Row` rather than an `Align`, which rendered centred here:
                // the column stretches its children, so the alignment had a
                // full-width box to sit in and no reason to leave it. Lining
                // up under "Revert all" is what makes the two read as the same
                // control at two scopes.
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _Revert(
                      label: 'Revert',
                      onTap: () => onRevert(change, index: i),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Revert extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _Revert({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(Radii.pill),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: kMinTouchTarget),
          padding: const EdgeInsets.symmetric(horizontal: Space.md),
          alignment: Alignment.center,
          child: Text(
            label,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: c.textMuted),
          ),
        ),
      ),
    );
  }
}
