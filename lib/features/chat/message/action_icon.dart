
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Claude-style message layout: user turns are compact right-aligned bubbles;
/// assistant turns are open prose — an ordered sequence of thinking, tool,
/// text, image, and artifact blocks — with a hover action row underneath.
class ActionIcon extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? color;

  const ActionIcon({super.key, 
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppSemanticColors>()!;
    return IconButton(
      tooltip: tooltip,
      iconSize: 15,
      visualDensity: VisualDensity.compact,
      color: color ?? colors.textSecondary,
      icon: Icon(icon),
      onPressed: onPressed,
    );
  }
}
