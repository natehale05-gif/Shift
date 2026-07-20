import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state/conversation_store.dart';
import '../state/home_shell_controller.dart';
import '../theme/app_colors.dart';
import '../widgets/common/app_nav_drawer.dart';
import '../widgets/common/command_palette.dart';
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
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  static const _screens = [
    ChatScreen(),
    MembershipScreen(),
    CultureScreen(),
    SettingsScreen(),
  ];

  void _openPalette() {
    showCommandPalette(
      context,
      onNavigate: (index) => setState(() => _index = index),
    );
  }

  void _newChat() {
    context.read<ConversationStore>().startNewConversation();
    setState(() => _index = 0);
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
            _openPalette,
        const SingleActivator(LogicalKeyboardKey.keyK, control: true):
            _openPalette,
        const SingleActivator(LogicalKeyboardKey.keyO,
            meta: true, shift: true): _newChat,
        const SingleActivator(LogicalKeyboardKey.keyO,
            control: true, shift: true): _newChat,
      },
      child: FocusScope(
        autofocus: true,
        child: _buildShell(context),
      ),
    );
  }

  Widget _buildShell(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 720;
        final body = IndexedStack(index: _index, children: _screens);
        final controller = HomeShellController(
          openDrawer: () => _scaffoldKey.currentState?.openDrawer(),
        );

        if (isWide) {
          // The rail already surfaces every destination, so no drawer is
          // needed here.
          return Provider<HomeShellController>.value(
            value: controller,
            child: Scaffold(
              body: Row(
                children: [
                  _FrostedPanel(
                    child: NavigationRail(
                      backgroundColor: Colors.transparent,
                      selectedIndex: _index,
                      onDestinationSelected: (i) =>
                          setState(() => _index = i),
                      labelType: NavigationRailLabelType.all,
                      leading: const _BrandMark(),
                      indicatorShape: const StadiumBorder(),
                      destinations: [
                        for (final d in homeShellDestinations)
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
            ),
          );
        }

        // Narrow layout: no bottom tab bar — every destination, plus chat
        // history, lives in the one hamburger-triggered drawer instead.
        return Provider<HomeShellController>.value(
          value: controller,
          child: Scaffold(
            key: _scaffoldKey,
            drawer: AppNavDrawer(
              currentIndex: _index,
              onSelect: (i) => setState(() => _index = i),
            ),
            body: body,
          ),
        );
      },
    );
  }
}

/// A translucent, blurred backdrop (macOS "sidebar material" vibrancy) with
/// a hairline trailing edge, used behind the NavigationRail so content is
/// faintly visible through it rather than a flat opaque panel.
class _FrostedPanel extends StatelessWidget {
  final Widget child;
  const _FrostedPanel({required this.child});

  @override
  Widget build(BuildContext context) {
    final side = BorderSide(color: Theme.of(context).dividerColor);
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.75),
            border: Border(right: side),
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
