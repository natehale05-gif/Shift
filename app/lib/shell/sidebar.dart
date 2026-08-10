import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/design/metrics.dart';
import '../core/design/palette.dart';
import '../features/chat/turn_controller.dart';

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
              child: _NewChat(
                onTap: () {
                  turn.clear();
                  onDismiss?.call();
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  Space.lg, Space.sm, Space.lg, Space.sm),
              child: Text('Recents',
                  style: text.labelSmall?.copyWith(color: c.textFaint)),
            ),
            Expanded(
              child: turn.isEmpty
                  // An empty list says so. A skeleton of fake rows here would
                  // be the same lie as a simulated reply.
                  ? Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: Space.lg, vertical: Space.sm),
                      child: Text(
                        'Conversations you start will be listed here. They '
                        'are not saved yet.',
                        style:
                            text.bodySmall?.copyWith(color: c.textFaint),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.symmetric(
                          horizontal: Space.sm),
                      children: [
                        _Row(
                          label: _firstLine(turn),
                          selected: true,
                          onTap: onDismiss,
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  static String _firstLine(TurnController turn) {
    for (final item in turn.items) {
      if (item is UserSaid) return item.text;
    }
    return 'New chat';
  }
}

class _NewChat extends StatelessWidget {
  final VoidCallback onTap;

  const _NewChat({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;

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
              Icon(Icons.add_rounded, size: 18, color: c.accent),
              const SizedBox(width: Space.sm),
              Text('New chat',
                  style: text.titleMedium?.copyWith(color: c.accent)),
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
