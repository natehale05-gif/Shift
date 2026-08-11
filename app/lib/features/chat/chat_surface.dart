import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/metrics.dart';
import '../../core/design/palette.dart';
import '../../core/design/typography.dart';
import '../../data/api_keys_store.dart';
import '../../data/image_store.dart';
import '../../shell/mode.dart';
import '../settings/settings_screen.dart';
import '../artifacts/artifact_card.dart';
import '../artifacts/artifact_panel.dart';
import '../visual/editing_image.dart';
import '../visual/image_viewer.dart';
import '../visual/made_image_view.dart';
import 'attached_notes.dart';
import 'composer.dart';
import 'private_banner.dart';
import 'failure_card.dart';
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

  /// The narrowest the conversation can be and still be worth having beside
  /// the panel — about a phone's width, which is a shape people read all day.
  static const double _minimumColumn = 420;

  @override
  Widget build(BuildContext context) {
    final turn = context.watch<TurnController>();

    final conversation = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: column),
        child: turn.isEmpty
            ? const _EmptyConversation()
            : _Transcript(turn: turn),
      ),
    );

    final artifact = turn.openArtifact;
    if (artifact == null) return conversation;

    // Beside the conversation when both can be usable, and over it when they
    // cannot. A *layout* question, so it reads the space it has rather than
    // the device class the way Code mode's surfaces will.
    //
    // Measured against what the conversation needs to stay usable, not against
    // [column], which is its comfortable *maximum*. Written the other way
    // first, and a 1300pt window put the panel full-screen with 1040pt of room
    // going spare — taking the transcript and the composer with it, so there
    // was no way to reply to the thing being previewed.
    return LayoutBuilder(
      builder: (context, constraints) {
        final together =
            constraints.maxWidth >= ArtifactPanel.width + _minimumColumn;
        if (!together) {
          return Stack(
            children: [
              conversation,
              Positioned.fill(
                child: ArtifactPanel(
                  artifact: artifact,
                  onClose: () => turn.showArtifact(null),
                ),
              ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: conversation),
            SizedBox(
              width: ArtifactPanel.width,
              child: ArtifactPanel(
                artifact: artifact,
                onClose: () => turn.showArtifact(null),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The composer, with whatever notes are going with the next message.
///
/// Built here rather than inline because the composer appears twice — on the
/// empty state and under a conversation — and both need the same attachments.
class _ChatComposer extends StatelessWidget {
  final String hint;
  final bool withStop;

  const _ChatComposer({this.hint = 'How can I help you today?', this.withStop = false});

  @override
  Widget build(BuildContext context) {
    final turn = context.watch<TurnController>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Above the composer rather than at the top of the screen, so it stays
        // in view as a long conversation scrolls — a private chat is private
        // for its whole length, not just at the beginning.
        if (turn.private) const PrivateBanner(),
        Composer(
      hint: hint,
      busy: withStop && turn.running,
      onStop: withStop ? turn.stop : null,
      onSend: (t) => turn.send(t, mode: AppMode.chat),
      // Both, and in this order: the picture being changed is the more
      // consequential of the two, so it sits nearest the text being typed
      // about it.
      attachments: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (turn.editingImage case final id?)
            EditingImage(id: id, onCancel: () => turn.editImage(null)),
          AttachedNotes(
            ids: turn.attachedNotes,
            onChanged: turn.attachNotes,
          ),
        ],
      ),
      onAttach: () async {
        final picked = await NotePicker.show(context,
            attached: List.of(turn.attachedNotes));
        if (picked != null) turn.attachNotes(picked);
      },
        ),
      ],
    );
  }
}

class _EmptyConversation extends StatelessWidget {
  const _EmptyConversation();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
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
          const _ChatComposer(),
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
          child: const _ChatComposer(hint: 'Reply to SHIFT', withStop: true),
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
                FailureCard(reply: reply),
              ],
              if (!reply.done && reply.text.isEmpty && reply.failure == null)
                Text('Thinking…',
                    style: text.bodyMedium?.copyWith(color: c.textFaint)),
              // Above the artifact card and below the prose, which is the
              // order they were made in. A picture is the answer when there is
              // one, so it is shown rather than described.
              for (final id in reply.imageIds)
                Padding(
                  padding: const EdgeInsets.only(top: Space.sm),
                  child: ConstrainedBox(
                    // Capped rather than full-width: a portrait image given
                    // the whole column pushes the reply and every control
                    // under it off the screen.
                    constraints: const BoxConstraints(maxHeight: 420),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: MadeImageView(
                        id: id,
                        prompt:
                            context.read<ImageStore>().record(id)?.prompt ??
                                '',
                        onTap: () => showImageViewer(
                          context,
                          id,
                          turns: context.read<TurnController>(),
                        ),
                      ),
                    ),
                  ),
                ),
              if (reply.artifactId case final id?)
                Builder(builder: (context) {
                  final made = context.read<TurnController>().byId(id);
                  return made == null
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.only(top: Space.sm),
                          child: ArtifactCard(
                            artifact: made,
                            onOpen: () =>
                                context.read<TurnController>().showArtifact(id),
                          ),
                        );
                }),
              if (reply.done) MessageActions(reply: reply),
            ],
          ),
        ),
    };
  }
}
