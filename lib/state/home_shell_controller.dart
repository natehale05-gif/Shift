import 'package:flutter/foundation.dart';

/// Lets a nested top-level screen (each has its own Scaffold) reach back to
/// the app shell's navigation Drawer. `Scaffold.of(context)` inside a screen
/// only finds that screen's own Scaffold, never the shell's outer one, so
/// this is threaded down via Provider instead.
class HomeShellController {
  final VoidCallback openDrawer;

  const HomeShellController({required this.openDrawer});
}
