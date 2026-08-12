import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../core/design/metrics.dart';
import '../../core/design/palette.dart';
import '../../data/agent.dart';
import '../../data/agent_store.dart';
import 'code_chrome.dart';

/// Whether this device can point at a folder on itself.
///
/// A phone has no filesystem to offer and a browser has no directory picker, so
/// on those two the answer is no and the sheet says why rather than showing a
/// control that fails when pressed. This is the same split the mode is built
/// around: a folder where the OS allows one, a server workspace everywhere
/// else.
bool get canPickFolder =>
    !kIsWeb &&
    const {TargetPlatform.linux, TargetPlatform.macOS, TargetPlatform.windows}
        .contains(defaultTargetPlatform);

/// Where a workspace comes from.
///
/// Modelled on the reference's sheet — X, a centred title, then the sources —
/// but honest about which of them exist. GitHub is listed and disabled rather
/// than hidden: knowing it is coming is worth more than a shorter sheet, and a
/// sheet with one row reads like something is broken.
class AddWorkspaceSheet extends StatelessWidget {
  const AddWorkspaceSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        backgroundColor: context.colors.surface,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(Radii.xl)),
        ),
        builder: (_) => const AddWorkspaceSheet(),
      );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                // The mode's own circle rather than an `IconButton`, whose
                // default is a 40pt target — and which would be the one control
                // here that did not match every other header in Code mode.
                CodeCircleButton(
                  icon: Icons.close_rounded,
                  tooltip: 'Close',
                  onTap: () => Navigator.of(context).maybePop(),
                ),
                Expanded(
                  child: Text(
                    'Add Workspace',
                    textAlign: TextAlign.center,
                    style: text.titleMedium
                        ?.copyWith(color: c.text, fontWeight: FontWeight.w600),
                  ),
                ),
                // Balances the circle so the title is centred on the sheet
                // rather than on what is left of it.
                const SizedBox(width: kMinTouchTarget + Space.sm),
              ],
            ),
            const SizedBox(height: Space.md),
            _Source(
              icon: Icons.folder_outlined,
              title: 'A folder on this computer',
              detail: canPickFolder
                  ? 'The agent reads and edits it directly'
                  : 'Only on the desktop app — this device has no folder to '
                      'point at',
              onTap: canPickFolder ? () => _pickFolder(context) : null,
            ),
            _Source(
              icon: Icons.hub_outlined,
              title: 'A GitHub repository',
              detail: 'Needs the server workspace, which is not built yet',
              onTap: null,
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> _pickFolder(BuildContext context) async {
    final agents = context.read<AgentStore>();
    final path = await getDirectoryPath(confirmButtonText: 'Use this folder');
    if (path == null || !context.mounted) return;

    await agents.addWorkspace(LocalFolder(
      id: 'ws-${DateTime.now().microsecondsSinceEpoch}',
      // The folder's own name, which is what a person calls the repository.
      // The full path would fill the row and ellipsise away the useful end.
      name: p.basename(p.normalize(path)),
      path: path,
    ));
    if (context.mounted) Navigator.of(context).maybePop();
  }
}

class _Source extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback? onTap;

  const _Source({
    required this.icon,
    required this.title,
    required this.detail,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final on = onTap != null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.md),
        child: Container(
          constraints: const BoxConstraints(minHeight: kMinTouchTarget),
          padding: const EdgeInsets.symmetric(vertical: Space.md),
          child: Row(
            children: [
              Icon(icon, size: 22, color: on ? c.text : c.textFaint),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title,
                        style: text.titleMedium
                            ?.copyWith(color: on ? c.text : c.textFaint)),
                    const SizedBox(height: Space.xxs),
                    Text(detail,
                        style: text.bodySmall?.copyWith(color: c.textFaint)),
                  ],
                ),
              ),
              if (on)
                Icon(Icons.chevron_right_rounded, size: 20, color: c.textFaint),
            ],
          ),
        ),
      ),
    );
  }
}
