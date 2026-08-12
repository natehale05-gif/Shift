import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/agent.dart';
import '../../data/agent_store.dart';
import '../../turn/request_title.dart';
import 'agent_runner.dart';
import 'agent_screen.dart';
import 'code_chrome.dart';

/// Turns a line typed into a composer into a running agent.
///
/// One function rather than a copy in each of the four screens that has a
/// composer: creating an agent, naming it, starting it and opening it is one
/// action, and four copies would be four chances for a screen to skip a step —
/// most likely the opening, which is what makes the run visible.
Future<void> startAgent(
  BuildContext context, {
  required String workspaceId,
  required String instruction,
}) async {
  final agents = context.read<AgentStore>();
  final runner = context.read<AgentRunner>();

  final agent = Agent(
    id: 'agent-${DateTime.now().microsecondsSinceEpoch}',
    // The same rule that names artifacts: "build me a login page" is a request,
    // "Login page" is a name. A list of requests reads as a chat log.
    title: titleFromRequest(instruction, fallback: 'New agent'),
    workspaceId: workspaceId,
    status: AgentStatus.working,
    updatedAt: DateTime.now(),
  );
  await agents.save(agent);

  if (!context.mounted) return;
  // Pushed before the run is awaited, so the work is watched rather than
  // waited out on the screen it was started from.
  unawaited(runner.send(agent, instruction));
  await Navigator.of(context)
      .push(codeRoute((_) => AgentScreen(agentId: agent.id)));
}

/// Which workspace a composer outside a workspace should start in.
///
/// One workspace is unambiguous, so use it. More than one is a genuine question
/// and the honest answer is to ask rather than to guess — starting an agent in
/// the wrong repository is work done in the wrong place.
String? soleWorkspaceOf(AgentStore agents) =>
    agents.workspaces.length == 1 ? agents.workspaces.single.id : null;

/// Reports that a composer had nowhere to start.
void reportNoWorkspace(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('Open a workspace first — that is where an agent runs.'),
    ),
  );
}
