import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/design/metrics.dart';
import '../core/design/palette.dart';
import 'mode.dart';
import 'mode_menu.dart';
import '../features/design/design_surface.dart';
import '../features/visual/visual_surface.dart';
import 'sidebar.dart';
import '../features/chat/chat_surface.dart';
import '../features/chat/private_toggle.dart';
import '../features/code/code_surface.dart';
import '../features/notes/notes_surface.dart';
import '../features/work/work_surface.dart';
import 'shell_controller.dart';

/// The frame every mode lives inside.
///
/// **One switcher on every device.** This was a rail on desktop and a
/// scrolling row of pills on a phone, chosen by device class. Both are gone in
/// favour of a single dropdown, which is simpler to hold in your head and, on
/// the phone, fixes the thing the pills spent most of their code apologising
/// for: six labelled destinations do not fit across a phone, so two of six
/// were always off-screen behind a scroll.
///
/// **A sidebar beside a column**, which is the shape of the app rather than a
/// detail of it: a conversation list on the left, one centred column of
/// content, and the composer inside that column. Persistent on a wide window,
/// a drawer on a phone. Without this the app was a top bar and a placeholder,
/// which is why recolouring it never made it resemble anything.
///
/// The device class still decides plenty — which surface Code mode gets, most
/// of all — so [deviceClassOf] and the override behind it stay. It just no
/// longer decides how you change mode.
class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    final shell = context.watch<ShellController>();

    // Code mode brings its own surface, and it takes the whole frame with it.
    //
    // A black body under a cream top bar and a cream sidebar does not read as
    // a mode with its own character; it reads as a rendering fault. So the
    // theme is swapped here rather than inside the mode, which is also what
    // keeps every shared control — the mode menu, the sidebar, the drawer —
    // working unchanged inside it.
    if (shell.mode == AppMode.code) {
      return Theme(
        data: Theme.of(context).copyWith(extensions: [ShiftColors.code]),
        child: Builder(builder: _frame),
      );
    }
    return _frame(context);
  }

  Widget _frame(BuildContext context) {
    final shell = context.watch<ShellController>();
    final c = context.colors;

    // Width, not device class. A sidebar is a question about how much room
    // there is right now — unlike Code mode's workbench, which is a question
    // about what kind of machine this is.
    final wide = MediaQuery.sizeOf(context).width >= 900;

    final content = Column(
      children: [
        _TopBar(wide: wide),
        Expanded(child: _ModeBody(mode: shell.mode)),
      ],
    );

    return Scaffold(
      backgroundColor: c.ground,
      drawer: wide
          ? null
          : Drawer(
              width: Sidebar.width,
              shape: const RoundedRectangleBorder(),
              // Closes itself once you have chosen. Without this the drawer
              // stayed open over the conversation it had just opened — on a
              // phone that is the whole screen, so picking a chat looked like
              // nothing had happened. `Sidebar` had the hook for this from the
              // start and the drawer was the one caller not passing it.
              child: Builder(
                builder: (context) => Sidebar(
                  onDismiss: () => Navigator.of(context).maybePop(),
                ),
              ),
            ),
      body: SafeArea(
        child: wide
            ? Row(
                children: [
                  const Sidebar(),
                  Expanded(child: content),
                ],
              )
            : content,
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final bool wide;

  const _TopBar({required this.wide});

  @override
  Widget build(BuildContext context) {
    final shell = context.watch<ShellController>();

    // No rule under it, on purpose: the bar sits on the same paper as the
    // conversation, which is what keeps the app reading as one surface rather
    // than as stacked bars.
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          if (!wide)
            Builder(
              // Sized, for the same reason the ghost opposite it is: an
              // `IconButton` left to its own minimum measures 40 here, and
              // this app holds every control to 44. The ghost's own test found
              // that; this one was under it too and nothing had checked.
              builder: (context) => SizedBox.square(
                dimension: kMinTouchTarget,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  tooltip: 'Conversations',
                  icon: const Icon(Icons.menu_rounded, size: 20),
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
              ),
            )
          else
            const SizedBox(width: Space.sm),
          ModeMenu(current: shell.mode, onSelect: shell.openMode),
          const Spacer(),
          // Chat only. The other five have no private session to be in, and a
          // control that is present but inert is worse than one that is
          // absent — it invites a tap and then answers nothing.
          if (shell.mode == AppMode.chat) const PrivateChatToggle(),
          const SizedBox(width: Space.xs),
        ],
      ),
    );
  }
}

class _ModeBody extends StatelessWidget {
  final AppMode mode;

  const _ModeBody({required this.mode});

  @override
  Widget build(BuildContext context) {
    // An exhaustive switch, so adding a seventh mode is a decision here rather
    // than something a default answers on somebody\'s behalf.
    return switch (mode) {
      // Chat is the one that exists. The other five still say so.
      AppMode.chat => const ChatSurface(),
      AppMode.code => const CodeSurface(),
      AppMode.visual => const VisualSurface(),
      AppMode.design => const DesignSurface(),
      AppMode.work => const WorkSurface(),
      AppMode.notes => const NotesSurface(),
    };
  }
}
