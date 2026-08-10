import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/metrics.dart';
import '../../core/design/palette.dart';
import '../../core/design/typography.dart';
import '../../data/api_keys_store.dart';
import '../../shell/mode.dart';
import '../settings/settings_screen.dart';
import 'composer.dart';
import 'markdown_view.dart';
import 'message_actions.dart';
import 'turn_controller.dart';

/// The conversation, laid out the way Claude's is.
///
/// Three decisions carry the resemblance, and none of them is colour:
///
/// * **The composer is the centre of an empty screen** and drops to the bottom
///   once there is a conversation. That single move is most of what the app
///   feels like on opening — an invitation rather than a blank document.
/// * **One centred column at a fixed measure**, not full-bedth text. A reply
///   running the width of a desktop window is unreadable, and the column is
///   what makes a wide window feel considered rather than empty.
/// * **The reply is prose, the interface is not.** Assistant text is set in
///   the serif at reading size; everything around it stays in the UI face.
class ChatSurface extends StatelessWidget {
  const ChatSurface({super.key});

  /// Claude's measure. Wide enough for code to breathe, narrow enough that a
  /// paragraph does not need a head-turn to read.
  static const double column = 720;

  @override
  Widget build(BuildContext context) {
    final turn = context.watch<TurnController>();

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: column),
        child: turn.isEmpty
            ? const _EmptyConversation()
            : _Transcript(turn: turn),
      ),
    );
  }
}

class _EmptyConversation extends StatelessWidget {
  const _EmptyConversation();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final turn = context.read<TurnController>();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.lg),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.auto_awesome, size: 22, color: c.accent),
              const SizedBox(width: Space.md),
              // Flexible, and it has to be: a fixed Row with 26pt text
              // overflowed a 393pt phone by 167 pixels, which the widget test
              // caught before the build did. A greeting that runs off the
              // edge of the screen is the first thing anyone would see.
              Flexible(
                child: Text(
                  'What are we making?',
                  style: ShiftType.proseStyle(c.text).copyWith(fontSize: 26),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.xl),
          Composer(onSend: (t) => turn.send(t, mode: AppMode.chat)),
          const SizedBox(height: Space.md),
          // Says the state and offers the fix in the same breath. The previous
          // version said only the state, and the way to act on it was three
          // steps away behind a hamburger — which is exactly the question this
          // screen prompted.
          if (context.watch<ApiKeysStore>().keyed.isEmpty)
            TextButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SettingsScreen(),
                ),
              ),
              icon: Icon(Icons.key_rounded, size: 16, color: c.textMuted),
              label: Text(
                'No provider connected — add a key',
                style: text.bodySmall?.copyWith(color: c.textMuted),
              ),
            ),
        ],
      ),
    );
  }
}

class _Transcript extends StatelessWidget {
  final TurnController turn;

  const _Transcript({required this.turn});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(
                Space.lg, Space.lg, Space.lg, Space.sm),
            itemCount: turn.items.length,
            itemBuilder: (context, i) => _Item(item: turn.items[i]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
              Space.lg, 0, Space.lg, Space.lg),
          child: Composer(
            busy: turn.running,
            hint: 'Reply to SHIFT',
            onSend: (t) => turn.send(t, mode: AppMode.chat),
            onStop: turn.stop,
          ),
        ),
      ],
    );
  }
}

class _Item extends StatelessWidget {
  final ChatItem item;

  const _Item({required this.item});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;

    return switch (item) {
      // The user's turn is a tinted block, inset from the left and not full
      // width — which is what makes a transcript scannable at a glance without
      // any avatars or name labels.
      UserSaid(:final text) => Padding(
          padding: const EdgeInsets.only(bottom: Space.lg, left: Space.xxl),
          child: Align(
            alignment: Alignment.centerRight,
            child: Container(
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(Radii.lg),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: Space.lg,
                vertical: Space.md,
              ),
              child: SelectableText(
                text,
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(color: c.text),
              ),
            ),
          ),
        ),
      Reply reply => Padding(
          padding: const EdgeInsets.only(bottom: Space.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Markdown, not plain text. Before this a reply containing a
              // list rendered as literal asterisks and a code block as
              // backticks — which is the first thing anyone sees after
              // "hello", because it is what a model answers with.
              if (reply.text.isNotEmpty) MarkdownView(reply.text),
              if (reply.failure != null) ...[
                if (reply.text.isNotEmpty) const SizedBox(height: Space.md),
                // A failure is stated in place, in the interface face, so it
                // is never mistaken for something a model said.
                Container(
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(Radii.md),
                    border: Border.all(color: c.border),
                  ),
                  padding: const EdgeInsets.all(Space.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline_rounded,
                              size: 18, color: c.textMuted),
                          const SizedBox(width: Space.sm),
                          Expanded(
                            child: Text(
                              reply.failure!,
                              style:
                                  text.bodyMedium?.copyWith(color: c.textMuted),
                            ),
                          ),
                        ],
                      ),

                      // A message that names a destination should be able to
                      // get you there. Without this the remedy is "open the
                      // drawer, scroll to the bottom, find Settings" — three
                      // steps the sentence does not mention, on a screen where
                      // the sidebar is hidden behind a hamburger. Asked about
                      // directly, which is how a discoverability problem
                      // usually surfaces: as a question, not as a bug report.
                      if (reply.failure!.contains('Settings')) ...[
                        const SizedBox(height: Space.sm),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const SettingsScreen(),
                              ),
                            ),
                            icon: Icon(Icons.key_rounded,
                                size: 16, color: c.accent),
                            label: Text(
                              'Add a key',
                              style:
                                  text.labelLarge?.copyWith(color: c.accent),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              if (!reply.done && reply.text.isEmpty && reply.failure == null)
                Text('Thinking…',
                    style: text.bodyMedium?.copyWith(color: c.textFaint)),
              if (reply.done && reply.failure == null)
                MessageActions(reply: reply),
            ],
          ),
        ),
    };
  }
}
