


import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import 'package:flutter/material.dart';


/// Claude-style composer: a single rounded card holding the text field with
/// a row of controls beneath it — an attach button, a model chip, and a
/// circular purple send button.
enum ComposerTool { webSearch, deepResearch, codeExecution, extendedThinking }

class ToolsMenu extends StatelessWidget {
  final bool webSearch;
  final bool deepResearch;
  final bool codeExecution;
  final bool extendedThinking;
  final ValueChanged<ComposerTool> onToggle;

  const ToolsMenu({super.key, 
    required this.webSearch,
    required this.deepResearch,
    required this.codeExecution,
    required this.extendedThinking,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppSemanticColors>()!;
    final anyActive = webSearch || deepResearch || codeExecution;
    return PopupMenuButton<ComposerTool>(
      tooltip: 'Tools',
      position: PopupMenuPosition.over,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      onSelected: onToggle,
      itemBuilder: (context) => [
        CheckedPopupMenuItem(
          value: ComposerTool.webSearch,
          checked: webSearch,
          child: const Text('Web search'),
        ),
        CheckedPopupMenuItem(
          value: ComposerTool.deepResearch,
          checked: deepResearch,
          child: const Text('Deep research'),
        ),
        CheckedPopupMenuItem(
          value: ComposerTool.codeExecution,
          checked: codeExecution,
          child: const Text('Code execution'),
        ),
        CheckedPopupMenuItem(
          value: ComposerTool.extendedThinking,
          checked: extendedThinking,
          child: const Text('Extended thinking'),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(
          Icons.add_circle_outline_rounded,
          size: 20,
          color: anyActive ? theme.colorScheme.primary : colors.textSecondary,
        ),
      ),
    );
  }
}

/// Interrupts a streaming reply — shown in place of the send button while a
/// generation is in flight (Claude's stop control).
