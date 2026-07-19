import 'dart:ui';

import 'package:flutter/material.dart';

/// An [AppBar] with a frosted/vibrancy backdrop blur, matching the
/// translucent toolbar look of macOS and iOS chrome (System Chrome
/// Materials) rather than Material's flat, opaque app bar.
class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget title;
  final List<Widget>? actions;
  final Widget? leading;
  final PreferredSizeWidget? bottom;

  const GlassAppBar({
    super.key,
    required this.title,
    this.actions,
    this.leading,
    this.bottom,
  });

  @override
  Size get preferredSize => Size.fromHeight(
        kToolbarHeight + (bottom?.preferredSize.height ?? 0),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: AppBar(
          title: title,
          leading: leading,
          actions: actions,
          bottom: bottom,
          backgroundColor: theme.scaffoldBackgroundColor.withValues(alpha: 0.72),
        ),
      ),
    );
  }
}
