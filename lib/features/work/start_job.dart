import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/agent.dart';
import '../../turn/request_title.dart';
import 'job_screen.dart';
import 'work_runner.dart';

/// Turns a line typed into the composer into a running job.
///
/// The Code-mode twin of this exists for the same reason and the two are
/// deliberately not shared: they differ in every line that matters — a
/// different store, a different runner, and a route that does **not** carry
/// Code's dark chrome — so a shared version would be a function of three flags
/// that reads worse than either.
Future<void> startJob(
  BuildContext context, {
  required String workspaceId,
  required String instruction,
}) async {
  final folders = context.read<WorkAgents>();
  final runner = context.read<WorkRunner>();

  final job = Agent(
    id: 'job-${DateTime.now().microsecondsSinceEpoch}',
    // "write me a summary of the Q3 notes" is a request; "Summary of the Q3
    // notes" is a name. A list of requests reads as a chat log.
    title: titleFromRequest(instruction, fallback: 'New job'),
    workspaceId: workspaceId,
    status: AgentStatus.working,
    updatedAt: DateTime.now(),
  );
  await folders.save(job);

  if (!context.mounted) return;
  // Pushed before the run is awaited, so the work is watched rather than
  // waited out on the screen it was started from.
  unawaited(runner.send(job, instruction));
  await Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => JobScreen(jobId: job.id)),
  );
}

/// Which folder a composer outside a folder should work in.
///
/// One folder is unambiguous. More than one is a genuine question, and guessing
/// means an agent editing the wrong person's documents.
String? soleFolderOf(WorkAgents folders) =>
    folders.workspaces.length == 1 ? folders.workspaces.single.id : null;

/// Reports that the composer had nowhere to work.
void reportNoFolder(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('Add a folder first — that is where the work happens.'),
    ),
  );
}
