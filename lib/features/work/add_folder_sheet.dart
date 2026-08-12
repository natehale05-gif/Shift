import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../agents/permission.dart';
import '../../core/design/metrics.dart';
import '../../core/design/palette.dart';
import '../../data/agent.dart';
import '../code/add_workspace_sheet.dart' show canPickFolder;
import 'work_runner.dart';

/// Adding a folder, and choosing what may happen in it without asking.
///
/// The two are one step on purpose. A permission mode buried in a settings
/// screen is one nobody sets, and "what is this agent allowed to do to my
/// files" is a question worth answering while you are looking at the folder you
/// just picked rather than a week later.
class AddFolderSheet extends StatefulWidget {
  const AddFolderSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        backgroundColor: context.colors.surface,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.xl)),
        ),
        builder: (_) => const AddFolderSheet(),
      );

  @override
  State<AddFolderSheet> createState() => _AddFolderSheetState();
}

class _AddFolderSheetState extends State<AddFolderSheet> {
  PermissionMode _mode = PermissionMode.ask;

  Future<void> _pick() async {
    final folders = context.read<WorkAgents>();
    final path = await getDirectoryPath(confirmButtonText: 'Use this folder');
    if (path == null || !mounted) return;

    await folders.addWorkspace(LocalFolder(
      id: 'folder-${DateTime.now().microsecondsSinceEpoch}',
      // The folder's own name. The full path would fill the row and ellipsise
      // away the end, which is the part that identifies it.
      name: p.basename(p.normalize(path)),
      path: path,
      permission: _mode,
    ));
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;

    return SafeArea(
      child: SingleChildScrollView(
        padding:
            const EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.lg, Space.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Add a folder',
                style: text.titleLarge
                    ?.copyWith(color: c.text, fontWeight: FontWeight.w700)),
            const SizedBox(height: Space.xs),
            Text(
              canPickFolder
                  ? 'The agent reads and edits the files in it directly. There '
                      'is no version control here, so what it changes is '
                      'changed.'
                  : 'Only in the desktop app — this device has no folder to '
                      'point at. The server workspace that would fix that is '
                      'not built yet.',
              style: text.bodyMedium?.copyWith(color: c.textMuted),
            ),
            const SizedBox(height: Space.lg),
            Text('What it may do without asking',
                style: text.bodyMedium?.copyWith(color: c.textMuted)),
            const SizedBox(height: Space.xs),
            for (final mode in PermissionMode.values)
              _ModeRow(
                mode: mode,
                selected: _mode == mode,
                onTap: () => setState(() => _mode = mode),
              ),
            const SizedBox(height: Space.lg),
            FilledButton(
              onPressed: canPickFolder ? _pick : null,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: Space.sm),
                child: Text('Choose a folder'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeRow extends StatelessWidget {
  final PermissionMode mode;
  final bool selected;
  final VoidCallback onTap;

  const _ModeRow({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.md),
        child: Container(
          constraints: const BoxConstraints(minHeight: kMinTouchTarget),
          padding: const EdgeInsets.symmetric(vertical: Space.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 20,
                  color: selected ? c.accent : c.textFaint,
                ),
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(mode.label,
                        style: text.titleMedium?.copyWith(color: c.text)),
                    const SizedBox(height: Space.xxs),
                    // The blurb is not decoration: "accept edits" and "don't
                    // ask" are indistinguishable from their names alone, and
                    // the difference between them is somebody's files.
                    Text(mode.blurb,
                        style: text.bodySmall?.copyWith(color: c.textFaint)),
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
