import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../data/stores/conversation_store.dart';
import '../state/home_shell_controller.dart';
import 'app_sidebar.dart';
import 'update_banner.dart';
import '../widgets/command_palette.dart';
import '../widgets/keyboard_shortcuts_sheet.dart';
import '../../features/chat/chat_screen.dart';
import '../../features/culture/culture_screen.dart';
import '../../features/membership/membership_screen.dart';
import '../../features/settings/settings_screen.dart';

/// Single-route app shell. Navigation between sections is purely local
/// state (an [IndexedStack] index) — the browser URL never changes, which
/// sidesteps the classic "Flutter web + GitHub Pages" deep-link 404 problem
/// entirely rather than working around it.
///
/// The sidebar (chat history + the profile button that reaches Membership,
/// Culture, and Settings) lives here, one level above the four screens, so
/// it persists across navigation instead of being rebuilt per screen.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  bool _sidebarOpen = true;
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

  /// Escape stops an in-flight generation (Claude's stop shortcut).
  void _onEscape() {
    final store = context.read<ConversationStore>();
    if (store.isStreaming) store.stopGeneration();
  }

  void _showShortcuts() => showKeyboardShortcuts(context);

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
            _openPalette,
        const SingleActivator(LogicalKeyboardKey.keyK, control: true):
            _openPalette,
        const SingleActivator(LogicalKeyboardKey.keyO, meta: true, shift: true):
            _newChat,
        const SingleActivator(
          LogicalKeyboardKey.keyO,
          control: true,
          shift: true,
        ): _newChat,
        const SingleActivator(LogicalKeyboardKey.slash, meta: true):
            _showShortcuts,
        const SingleActivator(LogicalKeyboardKey.slash, control: true):
            _showShortcuts,
        const SingleActivator(LogicalKeyboardKey.escape): _onEscape,
      },
      child: FocusScope(autofocus: true, child: _buildShell(context)),
    );
  }

  Widget _buildShell(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 720;
        final body = Column(
          children: [
            const UpdateBanner(),
            Expanded(child: IndexedStack(index: _index, children: _screens)),
          ],
        );
        final controller = HomeShellController(
          openDrawer: () => _scaffoldKey.currentState?.openDrawer(),
          toggleSidebar: () => setState(() => _sidebarOpen = !_sidebarOpen),
          navigateTo: (i) => setState(() => _index = i),
        );
        final sidebar = AppSidebar(
          currentIndex: _index,
          onNavigate: (i) => setState(() => _index = i),
        );

        if (isWide) {
          return Provider<HomeShellController>.value(
            value: controller,
            child: Scaffold(
              body: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    width: _sidebarOpen ? 280 : 0,
                    child: ClipRect(
                      child: OverflowBox(
                        alignment: Alignment.centerLeft,
                        minWidth: 280,
                        maxWidth: 280,
                        child: sidebar,
                      ),
                    ),
                  ),
                  Expanded(child: body),
                ],
              ),
            ),
          );
        }

        // Narrow layout: the same sidebar, opened as a Drawer from the
        // hamburger button each screen shows in its own app bar.
        return Provider<HomeShellController>.value(
          value: controller,
          child: Scaffold(
            key: _scaffoldKey,
            drawer: Drawer(
              width: 280,
              child: AppSidebar(
                currentIndex: _index,
                onNavigate: (i) => setState(() => _index = i),
                onActivated: () => Navigator.of(context).pop(),
              ),
            ),
            body: body,
          ),
        );
      },
    );
  }
}
