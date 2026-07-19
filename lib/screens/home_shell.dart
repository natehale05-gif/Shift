import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'chat/chat_screen.dart';
import 'culture/culture_screen.dart';
import 'membership/membership_screen.dart';
import 'settings/settings_screen.dart';

/// Single-route app shell. Navigation between sections is purely local
/// state (an [IndexedStack] index) — the browser URL never changes, which
/// sidesteps the classic "Flutter web + GitHub Pages" deep-link 404 problem
/// entirely rather than working around it.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _destinations = [
    (icon: Icons.chat_bubble_outline_rounded, selectedIcon: Icons.chat_bubble_rounded, label: 'Chat'),
    (icon: Icons.workspace_premium_outlined, selectedIcon: Icons.workspace_premium_rounded, label: 'Membership'),
    (icon: Icons.groups_outlined, selectedIcon: Icons.groups_rounded, label: 'Culture'),
    (icon: Icons.settings_outlined, selectedIcon: Icons.settings_rounded, label: 'Settings'),
  ];

  static const _screens = [
    ChatScreen(),
    MembershipScreen(),
    CultureScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 720;
        final body = IndexedStack(index: _index, children: _screens);

        if (isWide) {
          return Scaffold(
            body: Row(
              children: [
                _FrostedPanel(
                  edge: _FrostedEdge.right,
                  child: NavigationRail(
                    backgroundColor: Colors.transparent,
                    selectedIndex: _index,
                    onDestinationSelected: (i) => setState(() => _index = i),
                    labelType: NavigationRailLabelType.all,
                    leading: const _BrandMark(),
                    indicatorShape: const StadiumBorder(),
                    destinations: [
                      for (final d in _destinations)
                        NavigationRailDestination(
                          icon: Icon(d.icon),
                          selectedIcon: Icon(d.selectedIcon),
                          label: Text(d.label),
                        ),
                    ],
                  ),
                ),
                Expanded(child: body),
              ],
            ),
          );
        }

        return Scaffold(
          body: body,
          bottomNavigationBar: _FrostedPanel(
            edge: _FrostedEdge.top,
            child: NavigationBar(
              backgroundColor: Colors.transparent,
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: [
                for (final d in _destinations)
                  NavigationDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
                    label: d.label,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

enum _FrostedEdge { right, top }

/// A translucent, blurred backdrop (macOS "sidebar material" / iOS tab-bar
/// vibrancy) with a hairline edge, used behind the primary navigation chrome
/// so content is faintly visible through it rather than a flat opaque panel.
class _FrostedPanel extends StatelessWidget {
  final Widget child;
  final _FrostedEdge edge;
  const _FrostedPanel({required this.child, required this.edge});

  @override
  Widget build(BuildContext context) {
    final side = BorderSide(color: Theme.of(context).dividerColor);
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.75),
            border: edge == _FrostedEdge.right
                ? Border(right: side)
                : Border(top: side),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.accentDark, AppColors.accent],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 22),
          ),
        ],
      ),
    );
  }
}
