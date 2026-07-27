import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'liquid_glass.dart';

/// An [AppBar] rendered as Liquid Glass — a blurred, translucent toolbar
/// with a specular top highlight and a hairline bottom edge, matching the
/// System Chrome Materials look of iOS/macOS/visionOS rather than
/// Material's flat, opaque app bar.
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
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppSemanticColors>()!;
    return LiquidGlass(
      blurSigma: 28,
      tintOpacity: 0.62,
      border: Border(bottom: BorderSide(color: colors.border)),
      child: AppBar(
        title: title,
        leading: leading,
        actions: actions,
        bottom: bottom,
        backgroundColor: Colors.transparent,
      ),
    );
  }
}
