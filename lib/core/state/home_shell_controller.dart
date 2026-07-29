import 'package:flutter/foundation.dart';

/// Lets a nested top-level screen (each has its own Scaffold) reach back to
/// the app shell's navigation — the collapsible sidebar, its narrow-layout
/// drawer, and cross-section navigation (e.g. the profile menu jumping to
/// Settings) all live one level up, in [HomeShell].
class HomeShellController {
  final VoidCallback openDrawer;
  final VoidCallback toggleSidebar;
  final ValueChanged<int> navigateTo;

  const HomeShellController({
    required this.openDrawer,
    required this.toggleSidebar,
    required this.navigateTo,
  });
}
