import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/home_shell_controller.dart';

/// The one hamburger control every top-level screen uses to reach the
/// shell's sidebar: on wide layouts it toggles the persistent collapsible
/// panel in place; on narrow layouts it opens the same panel as a Drawer.
class HomeMenuButton extends StatelessWidget {
  const HomeMenuButton({super.key});

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final controller = context.read<HomeShellController>();
    return IconButton(
      tooltip: wide ? 'Toggle sidebar' : 'Menu',
      icon: Icon(wide ? Icons.view_sidebar_outlined : Icons.menu_rounded),
      onPressed: wide ? controller.toggleSidebar : controller.openDrawer,
    );
  }
}
