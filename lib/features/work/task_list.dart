import 'package:flutter/material.dart';

import '../../agents/agent_loop.dart';
import '../../core/design/metrics.dart';
import '../../core/design/palette.dart';
import '../../data/agent_run.dart';

/// The plan as it stands *now*, pinned above the transcript.
///
/// The mode's headline: you give it a job and then watch a list tick through
/// rather than watching a wall of tool calls. Distinct from the same list
/// appearing inside the transcript — that one is the record of a version of the
/// plan, this one is the current state, and the difference is why a job you
/// come back to after ten minutes is readable.
class TaskList extends StatelessWidget {
  final List<AgentTask> tasks;

  const TaskList({super.key, required this.tasks});

  /// The most recent plan in [run], or an empty list when it has never planned.
  ///
  /// Derived rather than stored on the run: the entries are the record, and a
  /// second copy of the same fact is a second thing that can be wrong.
  static List<AgentTask> latestIn(AgentRun run) =>
      run.entries.whereType<RunPlan>().lastOrNull?.tasks ?? const [];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    // Nothing planned yet is not an empty box: a job that has not said what it
    // intends to do has nothing to show, and a heading over no rows reads as
    // the list having failed to load.
    if (tasks.isEmpty) return const SizedBox.shrink();

    final done = tasks.where((t) => t.done).length;

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(bottom: BorderSide(color: c.divider)),
      ),
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Plan',
                  style: text.bodyMedium?.copyWith(color: c.textMuted)),
              const SizedBox(width: Space.xs),
              Text('$done of ${tasks.length}',
                  style: text.bodyMedium?.copyWith(color: c.textFaint)),
            ],
          ),
          const SizedBox(height: Space.xs),
          for (final task in tasks)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.xxs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      task.done
                          ? Icons.check_circle_rounded
                          : Icons.circle_outlined,
                      size: 16,
                      color: task.done ? c.success : c.textFaint,
                    ),
                  ),
                  const SizedBox(width: Space.xs),
                  Expanded(
                    child: Text(
                      task.title,
                      style: text.bodyMedium
                          ?.copyWith(color: task.done ? c.textMuted : c.text),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
