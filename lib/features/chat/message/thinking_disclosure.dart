
import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';

/// Claude-style message layout: user turns are compact right-aligned bubbles;
/// assistant turns are open prose — an ordered sequence of thinking, tool,
/// text, image, and artifact blocks — with a hover action row underneath.
class ThinkingDisclosure extends StatefulWidget {
  final String text;
  final bool streaming;

  const ThinkingDisclosure({super.key, required this.text, required this.streaming});

  @override
  State<ThinkingDisclosure> createState() => _ThinkingDisclosureState();
}


class _ThinkingDisclosureState extends State<ThinkingDisclosure> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppSemanticColors>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.psychology_alt_outlined,
                  size: 15,
                  color: colors.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  widget.streaming ? 'Thinking…' : 'Thought for a moment',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: colors.textSecondary),
                ),
                Icon(
                  _expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 16,
                  color: colors.textSecondary,
                ),
              ],
            ),
          ),
        ),
        if (_expanded)
          Container(
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: colors.border, width: 2),
              ),
            ),
            child: Text(
              widget.text,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: colors.textSecondary, height: 1.5),
            ),
          ),
      ],
    );
  }
}
