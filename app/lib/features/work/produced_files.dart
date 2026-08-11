import 'package:flutter/material.dart';

import '../../agents/workspace.dart';
import '../../core/design/metrics.dart';
import '../../core/design/palette.dart';
import '../../core/platform/save_file.dart';

/// What the job wrote, and a way to take it somewhere else.
///
/// The deliverable is the file in the folder — it is already saved, and this
/// list is not a download queue. Save a copy exists because "somewhere else" is
/// often the point: a report you want in your documents, not in the scratch
/// folder you pointed the agent at.
class ProducedFiles extends StatelessWidget {
  final List<String> paths;

  /// Null while the folder cannot be opened — a workspace that was removed, or
  /// a device with no filesystem. The list still renders, because *what it
  /// made* is worth knowing even where the bytes are out of reach.
  final AgentWorkspace? workspace;

  const ProducedFiles({super.key, required this.paths, this.workspace});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    if (paths.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: Space.md),
      decoration: BoxDecoration(
        color: c.surfaceRaised,
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      padding: const EdgeInsets.all(Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Files',
                  style: text.bodyMedium?.copyWith(color: c.textMuted)),
              const SizedBox(width: Space.xs),
              Text('${paths.length}',
                  style: text.bodyMedium?.copyWith(color: c.textFaint)),
            ],
          ),
          const SizedBox(height: Space.xs),
          for (final path in paths)
            _Row(path: path, workspace: workspace),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String path;
  final AgentWorkspace? workspace;

  const _Row({required this.path, this.workspace});

  Future<void> _save(BuildContext context) async {
    final open = workspace;
    if (open == null) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await open.readBytes(path);
      final saved = await saveFile(
        // The file's own name, not its path: a save dialog is asking what to
        // call it, and `reports/q3.md` is not a filename.
        suggestedName: path.split('/').last,
        bytes: bytes,
      );
      // Cancelling is not a failure, and saying "couldn't save" to somebody who
      // pressed Cancel is the app arguing with them.
      if (saved) {
        messenger.showSnackBar(const SnackBar(content: Text('Saved a copy.')));
      }
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not read $path — it may have moved.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;

    return Container(
      constraints: const BoxConstraints(minHeight: kMinTouchTarget),
      child: Row(
        children: [
          Icon(Icons.description_outlined, size: 18, color: c.textMuted),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Text(
              path,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.bodyMedium?.copyWith(
                color: c.text,
                fontFamily: 'monospace',
                fontFamilyFallback: const ['monospace'],
              ),
            ),
          ),
          if (workspace != null)
            IconButton(
              icon: const Icon(Icons.save_alt_rounded, size: 20),
              color: c.textMuted,
              tooltip: 'Save a copy',
              constraints: const BoxConstraints(
                minWidth: kMinTouchTarget,
                minHeight: kMinTouchTarget,
              ),
              onPressed: () => _save(context),
            ),
        ],
      ),
    );
  }
}
