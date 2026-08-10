import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/metrics.dart';
import '../../core/design/palette.dart';
import '../../data/agent.dart';
import '../../data/agent_store.dart';
import 'agent_row.dart';
import 'agent_screen.dart';
import 'code_chrome.dart';
import 'code_composer.dart';
import 'start_agent.dart';

/// A filtered list of agents — All Agents, Working, Needs Attention, In Review,
/// or the contents of one workspace.
///
/// One screen for all six, because they differ only in which agents they show
/// and what the title says. Six near-identical screens would be six places for
/// a row's layout to drift.
class AgentListScreen extends StatelessWidget {
  final String title;

  /// Null means "every agent".
  final AgentStatus? only;

  /// Set when this is a workspace's own list, which also drops the repository
  /// name from each row — inside a workspace every row would repeat it.
  final String? workspaceId;

  const AgentListScreen({
    super.key,
    required this.title,
    this.only,
    this.workspaceId,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final store = context.watch<AgentStore>();

    var agents = store.agents;
    if (only != null) agents = [for (final a in agents) if (a.status == only) a];
    if (workspaceId case final id?) {
      agents = [for (final a in agents) if (a.workspaceId == id) a];
    }

    // Grouped by state, in the order the states are declared — which is the
    // order that puts the things asking something of you first.
    final grouped = <AgentStatus, List<Agent>>{};
    for (final agent in agents) {
      grouped.putIfAbsent(agent.status, () => []).add(agent);
    }

    return Scaffold(
      backgroundColor: c.ground,
      body: SafeArea(
        child: Column(
          children: [
            CodeListHeader(
              title: title,
              leading: CodeCircleButton(
                icon: Icons.chevron_left_rounded,
                tooltip: 'Back',
                onTap: () => Navigator.of(context).maybePop(),
              ),
              actions: const [
                CodeCircleButton(icon: Icons.search_rounded, tooltip: 'Search'),
                CodeCircleButton(icon: Icons.tune_rounded, tooltip: 'Filter'),
              ],
            ),
            Expanded(
              child: agents.isEmpty
                  ? CodeEmpty(
                      title: 'No ${title.replaceAll('All ', '')}',
                      detail: only == AgentStatus.working
                          ? 'Agents that are actively working appear here'
                          : 'Nothing here yet',
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(
                        Space.lg,
                        0,
                        Space.lg,
                        CodeComposer.reservedHeight,
                      ),
                      children: [
                        // A single-state list needs no state headers — they
                        // would all say the same thing.
                        if (only != null && workspaceId == null)
                          CodeSection(
                            title: 'Recents',
                            children: [
                              for (final agent in agents)
                                _row(context, store, agent),
                            ],
                          )
                        else
                          for (final status in AgentStatus.values)
                            if (grouped[status] case final rows?)
                              CodeSection(
                                title: status.label,
                                children: [
                                  for (final agent in rows)
                                    _row(context, store, agent),
                                ],
                              ),
                      ],
                    ),
            ),
            CodeComposer(
              onSend: (text) {
                // Inside a workspace the target is obvious. Outside one it is
                // only obvious when there is exactly one.
                final target = workspaceId ?? soleWorkspaceOf(store);
                if (target == null) return reportNoWorkspace(context);
                startAgent(context,
                    workspaceId: target, instruction: text);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, AgentStore store, Agent agent) => AgentRow(
        agent: agent,
        workspaceName:
            workspaceId != null ? null : store.workspace(agent.workspaceId)?.name,
        onOpen: () => Navigator.of(context)
            .push(codeRoute((_) => AgentScreen(agentId: agent.id))),
      );
}
