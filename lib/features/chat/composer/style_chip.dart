


import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/stores/styles_store.dart';
import '../../styles/style_editor.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';


/// Claude-style composer: a single rounded card holding the text field with
/// a row of controls beneath it — an attach button, a model chip, and a
/// circular purple send button.
class StyleChip extends StatelessWidget {
  final String? styleOverride;
  final ValueChanged<String?> onSelected;

  const StyleChip({super.key, required this.styleOverride, required this.onSelected});

  Future<void> _createStyle(BuildContext context) async {
    final result = await showStyleEditorDialog(context);
    if (result == null || !context.mounted) return;
    final style = context.read<StylesStore>().create(result.$1, result.$2);
    onSelected(style.id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppSemanticColors>()!;
    final styles = context.watch<StylesStore>();
    final label = styleOverride == null
        ? 'Style'
        : styles.labelFor(styleOverride!) ?? 'Style';
    return PopupMenuButton<String>(
      tooltip: 'Response style',
      position: PopupMenuPosition.over,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      onSelected: (value) {
        if (value == '__create__') {
          _createStyle(context);
        } else {
          onSelected(value == 'default' ? null : value);
        }
      },
      itemBuilder: (context) => [
        CheckedPopupMenuItem(
          value: 'default',
          checked: styleOverride == null,
          child: const Text('Default (from Settings)'),
        ),
        for (final entry in builtInStyles.entries)
          CheckedPopupMenuItem(
            value: entry.key,
            checked: styleOverride == entry.key,
            child: Text(entry.value),
          ),
        if (styles.customStyles.isNotEmpty) const PopupMenuDivider(),
        for (final style in styles.customStyles)
          CheckedPopupMenuItem(
            value: style.id,
            checked: styleOverride == style.id,
            child: Text(style.name),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: '__create__',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_rounded, size: 16),
              SizedBox(width: 8),
              Text('Create style…'),
            ],
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(width: 2),
            Icon(Icons.expand_more_rounded, size: 14, color: colors.textSecondary),
          ],
        ),
      ),
    );
  }
}

/// Illustrative daily-usage indicator (Claude's plan-limit meter). Demo only —
/// nothing is metered or charged.
