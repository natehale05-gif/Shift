import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';

import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';

/// Shows the keyboard-shortcuts cheat sheet (⌘/ or Ctrl+/), like Claude's.
Future<void> showKeyboardShortcuts(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _ShortcutsDialog(),
  );
}

// Works on web too — reflects the browser's host OS.
bool get _isMac => defaultTargetPlatform == TargetPlatform.macOS;

class _ShortcutsDialog extends StatelessWidget {
  const _ShortcutsDialog();

  @override
  Widget build(BuildContext context) {
    final mod = _isMac ? '⌘' : 'Ctrl';
    final shortcuts = <(String, String)>[
      ('$mod K', 'Command palette'),
      ('$mod ⇧ O', 'New chat'),
      ('$mod /', 'Keyboard shortcuts'),
      ('Esc', 'Stop generating'),
      ('Enter', 'Send message'),
      ('⇧ Enter', 'New line'),
    ];
    return AlertDialog(
      title: const Text('Keyboard shortcuts'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (keys, label) in shortcuts)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(child: Text(label)),
                    _KeyCap(keys: keys),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _KeyCap extends StatelessWidget {
  final String keys;

  const _KeyCap({required this.keys});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppSemanticColors>()!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: colors.border),
      ),
      child: Text(
        keys,
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
