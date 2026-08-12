import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/design/metrics.dart';
import '../../core/design/palette.dart';
import '../../core/platform/save_file.dart';
import 'reply_document.dart';
import 'turn_controller.dart';

/// Copy, retry, and who answered — the row under a finished reply.
///
/// Always visible rather than revealed on hover: hover does not exist on the
/// device this is mostly used on, and a control that only appears to some of
/// your users is a control half of them will never find.
///
/// **Shown under a failed reply too.** It used to be hidden there, which meant
/// the one case where trying again is the obvious next move was the one case
/// with no button for it — the remedy was to retype the message. Copy drops out
/// instead when there is nothing to copy, because a control that copies an
/// empty string is worse than no control.
class MessageActions extends StatelessWidget {
  final Reply reply;

  const MessageActions({super.key, required this.reply});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final turn = context.read<TurnController>();

    return Padding(
      padding: const EdgeInsets.only(top: Space.sm),
      child: Row(
        children: [
          if (reply.text.isNotEmpty)
            _Action(
              icon: Icons.content_copy_rounded,
              tooltip: 'Copy',
              onTap: () => Clipboard.setData(ClipboardData(text: reply.text)),
            ),
          // A reply worth keeping is usually one you asked for here rather
          // than in Work mode, and Copy gets you asterisks and backticks in a
          // Word document.
          if (canSaveFile && reply.text.isNotEmpty && reply.failure == null)
            _Action(
              icon: Icons.description_outlined,
              tooltip: 'Save as a document',
              onTap: () => _saveDocument(context, turn, reply),
            ),
          // Retry re-runs the same request rather than replaying anything:
          // the plan is a pure function of the input, so asking again is
          // asking the same question, not repeating an answer.
          if (turn.canRetry)
            _Action(
              icon: Icons.refresh_rounded,
              tooltip: 'Try again',
              onTap: turn.retry,
            ),
          const Spacer(),
          if (reply.provider != null)
            Text(
              reply.provider!,
              style: text.labelSmall?.copyWith(color: c.textFaint),
            ),
          if (reply.interrupted) ...[
            const SizedBox(width: Space.sm),
            Text('stopped',
                style: text.labelSmall?.copyWith(color: c.textFaint)),
          ],
        ],
      ),
    );
  }
}

/// Writes the reply as a `.docx` the person chooses a home for.
///
/// The decision — what it is called and what is in it — is
/// [documentForReply], so it can be asserted without answering a save dialog.
Future<void> _saveDocument(
  BuildContext context,
  TurnController turn,
  Reply reply,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final document = documentForReply(
    prompt: turn.promptFor(reply) ?? '',
    markdown: reply.text,
  );
  final saved = await saveFile(
    suggestedName: document.name,
    bytes: document.bytes,
    mimeType:
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  );
  // Silent on a cancel: the person chose that, and an error there reads as a
  // failure they caused.
  if (saved) {
    messenger.showSnackBar(const SnackBar(content: Text('Saved.')));
  }
}

class _Action extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _Action({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: kMinTouchTarget,
        height: kMinTouchTarget,
        child: IconButton(
          onPressed: onTap,
          icon: Icon(icon, size: 16),
          color: c.textFaint,
        ),
      ),
    );
  }
}
