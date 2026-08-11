import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/ghost.dart';
import '../../core/design/metrics.dart';
import '../../core/design/palette.dart';
import 'delete_conversation.dart';
import 'turn_controller.dart';

/// The ghost in the corner: whether this chat is being kept, and the way to
/// change it.
///
/// **Privacy is a property of a conversation, not of a moment.** Turning it on
/// cannot unwrite what is already on disk, and turning it off cannot recover
/// what was never written — so a tap starts a fresh chat either way rather
/// than pretending to convert the one on screen. That is what the sidebar row
/// this replaces already did; the only new thing is that it now works in both
/// directions from a control you can see.
///
/// It replaced that row rather than joining it. Two controls for one setting
/// is the redundancy the Settings screen spent a wave removing, and it comes
/// with a second cost here: the two would each have their own idea of what the
/// state looks like.
class PrivateChatToggle extends StatelessWidget {
  const PrivateChatToggle({super.key});

  Future<void> _toggle(BuildContext context) async {
    final turn = context.read<TurnController>();

    if (!turn.private) {
      // Nothing is at risk going this way: the chat being left has been on
      // disk since its first message and stays there.
      turn.clear(private: true);
      return;
    }

    // Going the other way discards the private chat, which is what private
    // means — but a single tap is a thin thing to hang it on, so it asks.
    //
    // **Only when there is something to lose.** Confirming an empty chat away
    // is the kind of prompt that teaches people to dismiss prompts, and the
    // next one they dismiss is the one that mattered.
    if (turn.items.isNotEmpty) {
      final sure = await confirmLoss(
        context,
        question: 'Leave this private chat?',
        detail: 'It was never saved, so it goes when you leave. Nothing of '
            'it will be on this device.',
        action: 'Leave',
      );
      if (!sure) return;
    }

    turn.clear();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final private = context.watch<TurnController>().private;

    // Sized explicitly rather than left to the button's own minimum, which
    // measures 40 here — under the 44 this app holds itself to everywhere.
    // The test caught it on its first run, which is the fourth time that
    // check has earned its keep in this shell.
    return SizedBox.square(
      dimension: kMinTouchTarget,
      child: IconButton(
        padding: EdgeInsets.zero,
        // The tooltip is the label — an unlabelled hand-drawn glyph is legible
        // as a ghost and not as a *setting*, and this is also what a screen
        // reader announces.
        tooltip: private ? 'Leave private chat' : 'Private chat',
        onPressed: () => _toggle(context),
        icon: GhostIcon(
          size: 20,
          color: private ? c.accent : c.textMuted,
          filled: private,
        ),
      ),
    );
  }
}
