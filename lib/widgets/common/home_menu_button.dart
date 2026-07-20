import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/home_shell_controller.dart';

/// Leading hamburger for top-level screens that don't have a drawer of
/// their own — opens the shell's unified navigation drawer. Callers should
/// only use this below HomeShell's own 720px breakpoint; above that the
/// NavigationRail already surfaces every destination.
class HomeMenuButton extends StatelessWidget {
  const HomeMenuButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Menu',
      icon: const Icon(Icons.menu_rounded),
      onPressed: () => context.read<HomeShellController>().openDrawer(),
    );
  }
}
