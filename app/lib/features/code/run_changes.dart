import '../../agents/diff.dart';
import '../../agents/workspace.dart';
import '../../data/agent.dart';

/// One file a run changed, and how.
class FileChange {
  final String path;
  final List<Hunk> hunks;

  const FileChange({required this.path, required this.hunks});

  DiffStat get stat => DiffStat(
        added: hunks.fold(0, (sum, h) => sum + h.added),
        removed: hunks.fold(0, (sum, h) => sum + h.removed),
      );
}

/// What a run changed, as it stands **right now**.
///
/// Recomputed from disk on every ask rather than stored, because the answer
/// moves: reverting a hunk changes it, and so does the person editing the file
/// themselves between the run and the review. A stored diff would go stale
/// silently, which is the worst way for a review to be wrong.
///
/// A path whose content now equals its baseline is **dropped**. After reverting
/// everything in a file it is no longer a changed file, and listing it would
/// show a change that is not there.
Future<List<FileChange>> changesFor({
  required AgentWorkspace workspace,
  required List<String> paths,
  required Map<String, String> baseline,
}) async {
  final changes = <FileChange>[];

  for (final path in paths) {
    final before = baseline[path] ?? '';
    String after;
    try {
      after = await workspace.readText(path);
    } catch (_) {
      // Gone, or unreadable. Either way there is nothing there now, which
      // against a non-empty baseline is a deletion worth showing.
      after = '';
    }

    final hunks = diffHunks(before, after);
    if (hunks.isEmpty) continue;
    changes.add(FileChange(path: path, hunks: hunks));
  }

  return changes;
}

/// The whole run's line count, for the row in the list.
DiffStat totalOf(List<FileChange> changes) => DiffStat(
      added: changes.fold(0, (sum, c) => sum + c.stat.added),
      removed: changes.fold(0, (sum, c) => sum + c.stat.removed),
    );

/// Puts one hunk back, and leaves the rest.
///
/// Reverting is writing the file as it would be with every hunk applied
/// *except* this one — computed from the baseline, so it composes: revert
/// twice and two hunks are gone, because the next diff is taken against
/// whatever is on disk by then.
Future<void> revertHunk({
  required AgentWorkspace workspace,
  required FileChange change,
  required String baseline,
  required int index,
}) =>
    workspace.writeText(
      change.path,
      applyHunks(baseline, change.hunks, {
        for (var i = 0; i < change.hunks.length; i++)
          if (i != index) i,
      }),
    );

/// Puts the whole file back as it was before the run touched it.
Future<void> revertFile({
  required AgentWorkspace workspace,
  required FileChange change,
  required String baseline,
}) =>
    workspace.writeText(
      change.path,
      applyHunks(baseline, change.hunks, const {}),
    );
