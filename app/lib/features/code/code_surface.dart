import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/metrics.dart';
import '../../core/design/palette.dart';
import '../../data/agent.dart';
import '../../data/agent_store.dart';
import 'agent_list_screen.dart';
import 'code_chrome.dart';
import 'code_composer.dart';
import 'start_agent.dart';

/// Code mode's root: the Inbox.
///
/// Four cards over a list of workspaces, and that arrangement is the whole
/// argument of the mode — you arrive at *states*, not at files. The cards are
/// much taller than their content needs, deliberately: it is what gives this
/// screen its calm, and a tight grid of four counters would read as a
/// dashboard.
class CodeSurface extends StatelessWidget {
  const CodeSurface({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final store = context.watch<AgentStore>();

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
                Space.lg, 0, Space.lg, CodeComposer.reservedHeight),
            children: [
              Padding(
                padding: const EdgeInsets.only(
                    top: Space.sm, bottom: Space.lg),
                child: Text(
                  'Inbox',
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(color: c.text, fontWeight: FontWeight.w700),
                ),
              ),
              _Cards(store: store),
              const SizedBox(height: Space.xl),
              Text('Workspaces',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: c.textMuted)),
              const SizedBox(height: Space.xs),
              for (final workspace in store.workspaces)
                _WorkspaceRow(workspace: workspace),
              const _AddWorkspaceRow(),
            ],
          ),
        ),
        CodeComposer(
          onSend: (text) {
            final target = soleWorkspaceOf(store);
            if (target == null) return reportNoWorkspace(context);
            startAgent(context, workspaceId: target, instruction: text);
          },
        ),
      ],
    );
  }
}

class _Cards extends StatelessWidget {
  final AgentStore store;

  const _Cards({required this.store});

  @override
  Widget build(BuildContext context) {
    // A 2×2 grid whose cells are taller than they are wide on a phone and
    // squarer on a desktop. Fixed at 2 columns rather than responsive: four
    // states in a row reads as a toolbar, and one per line is a menu.
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - Space.md) / 2;
        final height = width < 200 ? width * 1.05 : 150.0;

        Widget card({
          required IconData icon,
          required Color colour,
          required String label,
          int? count,
          AgentStatus? status,
        }) =>
            SizedBox(
              width: width,
              height: height,
              child: _StatusCard(
                icon: icon,
                colour: colour,
                label: label,
                count: count,
                onOpen: () => Navigator.of(context).push(
                  codeRoute((_) => AgentListScreen(title: label, only: status)),
                ),
              ),
            );

        final c = context.colors;
        return Wrap(
          spacing: Space.md,
          runSpacing: Space.md,
          children: [
            card(
              icon: Icons.blur_on_rounded,
              colour: c.danger,
              label: 'All Agents',
            ),
            card(
              icon: Icons.more_horiz_rounded,
              colour: const Color(0xFF0A84FF),
              label: 'Working',
              count: store.count(AgentStatus.working),
              status: AgentStatus.working,
            ),
            card(
              icon: Icons.notifications_none_rounded,
              colour: c.warning,
              label: 'Needs Attention',
              count: store.count(AgentStatus.needsAttention),
              status: AgentStatus.needsAttention,
            ),
            card(
              icon: Icons.task_alt_rounded,
              colour: c.accent,
              label: 'In Review',
              count: store.count(AgentStatus.inReview),
              status: AgentStatus.inReview,
            ),
          ],
        );
      },
    );
  }
}

class _StatusCard extends StatelessWidget {
  final IconData icon;
  final Color colour;
  final String label;
  final int? count;
  final VoidCallback onOpen;

  const _StatusCard({
    required this.icon,
    required this.colour,
    required this.label,
    required this.onOpen,
    this.count,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.lg),
        onTap: onOpen,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.lg),
            border: Border.all(color: c.border),
          ),
          padding: const EdgeInsets.all(Space.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              Icon(icon, size: 26, color: colour),
              const SizedBox(height: Space.md),
              Row(
                children: [
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleMedium?.copyWith(
                          color: c.text, fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (count != null) ...[
                    const SizedBox(width: Space.xs),
                    // Grey text following the label, not a badge. A badge says
                    // "unread"; this is just how many there are.
                    Text('$count',
                        style: text.titleMedium?.copyWith(color: c.textFaint)),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkspaceRow extends StatelessWidget {
  final Workspace workspace;

  const _WorkspaceRow({required this.workspace});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;

    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => Navigator.of(context).push(
              codeRoute((_) => AgentListScreen(
                    title: workspace.name,
                    workspaceId: workspace.id,
                  )),
            ),
            child: Container(
              constraints: const BoxConstraints(minHeight: kMinTouchTarget),
              child: Row(
                children: [
                  Icon(Icons.folder_outlined, size: 20, color: c.textMuted),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: Text(
                      workspace.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleMedium?.copyWith(
                          color: c.text, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, size: 20, color: c.textFaint),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: Space.xl),
          child: Divider(height: 1, thickness: 1, color: c.divider),
        ),
      ],
    );
  }
}

class _AddWorkspaceRow extends StatelessWidget {
  const _AddWorkspaceRow();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;

    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            // Adding one needs a repository picker, which needs GitHub — the
            // next wave. The row is here because its absence changes the
            // screen's shape, and it says plainly that it is not ready rather
            // than doing nothing when pressed.
            onTap: null,
            child: Container(
              constraints: const BoxConstraints(minHeight: kMinTouchTarget),
              child: Row(
                children: [
                  Icon(Icons.create_new_folder_outlined,
                      size: 20, color: c.textFaint),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: Text('Add Workspace',
                        style: text.titleMedium?.copyWith(color: c.textFaint)),
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: Space.xl),
          child: Divider(height: 1, thickness: 1, color: c.divider),
        ),
      ],
    );
  }
}
