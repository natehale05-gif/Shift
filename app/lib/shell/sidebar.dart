import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/design/metrics.dart';
import '../core/design/palette.dart';
import '../data/conversation_store.dart';
import '../features/chat/turn_controller.dart';
import '../features/settings/settings_screen.dart';

/// The conversation list.
///
/// Persistent on a wide window and a drawer on a narrow one — which is what
/// Claude does, and what every app with a list beside a document does, because
/// a sidebar that eats half a phone is not a sidebar.
///
/// It is deliberately **not** on the same paper as the conversation: a step
/// darker, with no border between them. That tonal step is what separates the
/// two areas; a rule would make the app look like two panes bolted together.
class Sidebar extends StatelessWidget {
  final VoidCallback? onDismiss;

  const Sidebar({super.key, this.onDismiss});

  static const double width = 260;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final turn = context.watch<TurnController>();
    final saved = context.watch<ConversationStore>().index;

    return Container(
      width: width,
      color: c.surface,
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(Space.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _NewChat(
                    onTap: () {
                      turn.clear();
                      onDismiss?.call();
                    },
                  ),
                  _NewChat(
                    private: true,
                    onTap: () {
                      turn.clear(private: true);
                      onDismiss?.call();
                    },
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  Space.lg, Space.sm, Space.lg, Space.sm),
              child: Text('Recents',
                  style: text.labelSmall?.copyWith(color: c.textFaint)),
            ),
            Expanded(
              child: saved.isEmpty
                  // An empty list says so. A skeleton of fake rows here would
                  // be the same lie as a simulated reply.
                  ? Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: Space.lg, vertical: Space.sm),
                      child: Text(
                        'Conversations you start will be listed here.',
                        style:
                            text.bodySmall?.copyWith(color: c.textFaint),
                      ),
                    )
                  : ListView.builder(
                      padding:
                          const EdgeInsets.symmetric(horizontal: Space.sm),
                      itemCount: saved.length,
                      itemBuilder: (context, i) => _Row(
                        label: saved[i].title,
                        selected: saved[i].id == turn.conversationId,
                        onTap: () {
                          turn.open(saved[i].id);
                          onDismiss?.call();
                        },
                      ),
                    ),
            ),
            // Settings lives at the foot of the list, which is where it lives
            // in every app shaped like this — and it is the destination the
            // chat's own error message names, so it has to be findable from
            // wherever that message is read.
            Divider(height: 1, thickness: 1, color: c.divider),
            Padding(
              padding: const EdgeInsets.all(Space.sm),
              child: _SettingsEntry(onOpen: onDismiss),
            ),
          ],
        ),
      ),
    );
  }
}

class _NewChat extends StatelessWidget {
  final VoidCallback onTap;

  /// The private variant, in the muted ink rather than the accent: it is an
  /// alternative to the ordinary action, not a second thing competing with it.
  final bool private;

  const _NewChat({required this.onTap, this.private = false});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final ink = private ? c.textMuted : c.accent;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.md),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: kMinTouchTarget),
          padding: const EdgeInsets.symmetric(
              horizontal: Space.md, vertical: Space.sm),
          child: Row(
            children: [
              Icon(private ? Icons.visibility_off_outlined : Icons.add_rounded,
                  size: 18, color: ink),
              const SizedBox(width: Space.sm),
              // Flexible, because a fixed Row here overflowed the 260pt
              // sidebar by 54 pixels the moment a second, longer label
              // appeared — caught by the shell tests before the build.
              Flexible(
                child: Text(
                  // "Private chat" rather than "New private chat": it sits
                  // directly under "New chat", so the word is already there,
                  // and the longer label is what did not fit.
                  private ? 'Private chat' : 'New chat',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleMedium?.copyWith(color: ink),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const _Row({required this.label, required this.selected, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.sm),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: kMinTouchTarget),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: selected ? c.surfaceRaised : Colors.transparent,
            borderRadius: BorderRadius.circular(Radii.sm),
          ),
          padding: const EdgeInsets.symmetric(
              horizontal: Space.md, vertical: Space.sm),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.bodyMedium?.copyWith(color: c.text),
          ),
        ),
      ),
    );
  }
}

class _SettingsEntry extends StatelessWidget {
  final VoidCallback? onOpen;

  const _SettingsEntry({this.onOpen});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.sm),
        onTap: () {
          onOpen?.call();
          Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
          );
        },
        child: Container(
          constraints: const BoxConstraints(minHeight: kMinTouchTarget),
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(
              horizontal: Space.md, vertical: Space.sm),
          child: Row(
            children: [
              Icon(Icons.settings_outlined, size: 18, color: c.textMuted),
              const SizedBox(width: Space.sm),
              Text('Settings',
                  style: text.bodyMedium?.copyWith(color: c.textMuted)),
            ],
          ),
        ),
      ),
    );
  }
}
