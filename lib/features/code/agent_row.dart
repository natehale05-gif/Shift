import 'package:flutter/material.dart';

import '../../core/design/metrics.dart';
import '../../core/design/palette.dart';
import '../../data/agent.dart';

/// One agent in a list: a state dot, what it is called, and how it is going.
///
/// The metadata line is the same everywhere in the reference — a green tick and
/// "Checks Passed", the diff, then the repository — and it is what makes the
/// lists scannable without opening anything. Where a run failed, the note takes
/// that line instead, because "Unable To Complete Request" is more use than a
/// diff of zero.
class AgentRow extends StatelessWidget {
  final Agent agent;

  /// Omitted inside a workspace, where every row would repeat it.
  final String? workspaceName;

  final VoidCallback onOpen;

  const AgentRow({
    super.key,
    required this.agent,
    required this.onOpen,
    this.workspaceName,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        child: Container(
          constraints: const BoxConstraints(minHeight: kMinTouchTarget),
          padding: const EdgeInsets.symmetric(vertical: Space.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                // Aligned to the cap-height of the title rather than the top of
                // its line box, or the dot floats above the word it belongs to.
                padding: const EdgeInsets.only(top: 6),
                child: _StateDot(status: agent.status),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      agent.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleMedium?.copyWith(color: c.text),
                    ),
                    const SizedBox(height: Space.xxs),
                    _Meta(agent: agent, workspaceName: workspaceName),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StateDot extends StatelessWidget {
  final AgentStatus status;

  const _StateDot({required this.status});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    // Blue for the ones asking something of you, red for a run that stopped,
    // grey for everything settled. Three meanings, not six — a colour per
    // status would be a code nobody learns.
    final colour = switch (status) {
      AgentStatus.needsAttention || AgentStatus.working => const Color(0xFF0A84FF),
      AgentStatus.failed => c.danger,
      _ => c.textFaint,
    };

    return SizedBox(
      width: 10,
      height: 10,
      child: DecoratedBox(
        decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
      ),
    );
  }
}

/// The line under the title: a tick, the diff, the repository.
///
/// **One rich-text line rather than a Row**, and that is a fix rather than a
/// preference. As a Row it overflowed a 393pt phone the moment a workspace had
/// a long name — the fixed parts do not shrink and only the last child was
/// flexible, so the layout ran off the edge instead of ellipsising. A single
/// span chain has exactly one overflow behaviour and it is the right one.
class _Meta extends StatelessWidget {
  final Agent agent;
  final String? workspaceName;

  const _Meta({required this.agent, this.workspaceName});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final base = text.bodySmall?.copyWith(color: c.textMuted);

    // A failure says what happened. The numbers are meaningless there — a run
    // that could not complete has nothing to count.
    if (agent.note case final note? when agent.status == AgentStatus.failed) {
      return Text(note,
          maxLines: 1, overflow: TextOverflow.ellipsis, style: base);
    }

    final spans = <InlineSpan>[];
    void separate() {
      if (spans.isNotEmpty) {
        spans.add(TextSpan(
            text: '  ·  ', style: base?.copyWith(color: c.textFaint)));
      }
    }

    if (agent.checksPassed == true) {
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Padding(
          padding: const EdgeInsets.only(right: Space.xxs),
          child: Icon(Icons.check_rounded, size: 15, color: c.success),
        ),
      ));
      spans.add(TextSpan(text: 'Checks Passed', style: base));
    }
    if (!agent.diff.isEmpty) {
      separate();
      spans.add(TextSpan(text: '${agent.diff}', style: base));
    }
    if (workspaceName case final name?) {
      separate();
      spans.add(TextSpan(
          text: name, style: base?.copyWith(color: c.textFaint)));
    }

    if (spans.isEmpty) return const SizedBox.shrink();
    return Text.rich(
      TextSpan(children: spans),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: base,
    );
  }
}
