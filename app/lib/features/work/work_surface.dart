import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/metrics.dart';
import '../../core/design/palette.dart';
import '../../core/widgets/agent_composer.dart';
import '../../data/agent.dart';
import 'add_folder_sheet.dart';
import 'job_screen.dart';
import 'start_job.dart';
import 'work_runner.dart';

/// Work mode's root: your folders, and what has been done in them.
///
/// Deliberately not Code's Inbox. Code arrives at *states* — Needs Attention,
/// In Review — because a repository has many agents working at once. A folder
/// of documents has one job at a time and the question is "what did it do to my
/// files", so the list is jobs in the order they happened.
class WorkSurface extends StatelessWidget {
  const WorkSurface({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final folders = context.watch<WorkAgents>();

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
                Space.lg, Space.md, Space.lg, AgentComposer.reservedHeight),
            children: [
              Text('Work',
                  style: text.headlineMedium
                      ?.copyWith(color: c.text, fontWeight: FontWeight.w700)),
              const SizedBox(height: Space.xs),
              Text(
                'Point it at a folder and give it a job. It works through the '
                'files and writes what it makes back into the folder.',
                style: text.bodyMedium?.copyWith(color: c.textMuted),
              ),
              const SizedBox(height: Space.xl),
              Text('Folders',
                  style: text.bodyMedium?.copyWith(color: c.textMuted)),
              const SizedBox(height: Space.xs),
              for (final folder in folders.workspaces)
                _FolderRow(folder: folder),
              _AddFolderRow(),
              if (folders.agents.isNotEmpty) ...[
                const SizedBox(height: Space.xl),
                Text('Jobs',
                    style: text.bodyMedium?.copyWith(color: c.textMuted)),
                const SizedBox(height: Space.xs),
                for (final job in folders.agents)
                  _JobRow(job: job, folder: folders.workspace(job.workspaceId)),
              ],
            ],
          ),
        ),
        AgentComposer(
          hint: 'Give it a job…',
          onSend: (text) {
            final target = soleFolderOf(folders);
            if (target == null) return reportNoFolder(context);
            startJob(context, workspaceId: target, instruction: text);
          },
        ),
      ],
    );
  }
}

class _FolderRow extends StatelessWidget {
  final Workspace folder;

  const _FolderRow({required this.folder});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;

    return Column(
      children: [
        Container(
          constraints: const BoxConstraints(minHeight: kMinTouchTarget),
          child: Row(
            children: [
              Icon(Icons.folder_outlined, size: 20, color: c.textMuted),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      folder.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleMedium?.copyWith(
                          color: c.text, fontWeight: FontWeight.w600),
                    ),
                    // The standing answer, on the row. What an agent may do to
                    // your files without asking is not a detail to go looking
                    // for.
                    Text(folder.permission.label,
                        style: text.bodySmall?.copyWith(color: c.textFaint)),
                  ],
                ),
              ),
            ],
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

class _AddFolderRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => AddFolderSheet.show(context),
        child: Container(
          constraints: const BoxConstraints(minHeight: kMinTouchTarget),
          child: Row(
            children: [
              Icon(Icons.create_new_folder_outlined,
                  size: 20, color: c.textMuted),
              const SizedBox(width: Space.md),
              Expanded(
                child: Text('Add a folder',
                    style: text.titleMedium?.copyWith(color: c.textMuted)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _JobRow extends StatelessWidget {
  final Agent job;
  final Workspace? folder;

  const _JobRow({required this.job, this.folder});

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
              MaterialPageRoute<void>(
                  builder: (_) => JobScreen(jobId: job.id)),
            ),
            child: Container(
              constraints: const BoxConstraints(minHeight: kMinTouchTarget),
              child: Row(
                children: [
                  _Dot(status: job.status),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          job.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.titleMedium?.copyWith(color: c.text),
                        ),
                        Text(
                          [
                            job.note ?? job.status.label,
                            if (folder != null) folder!.name,
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall?.copyWith(color: c.textFaint),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      size: 20, color: c.textFaint),
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

/// Status as a colour, which is how a list of jobs is read at a glance.
class _Dot extends StatelessWidget {
  final AgentStatus status;

  const _Dot({required this.status});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final colour = switch (status) {
      AgentStatus.working => c.accent,
      AgentStatus.needsAttention => c.warning,
      AgentStatus.failed => c.danger,
      AgentStatus.inReview || AgentStatus.openPr || AgentStatus.read =>
        c.textFaint,
    };

    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
    );
  }
}
