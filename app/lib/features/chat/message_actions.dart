import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/design/metrics.dart';
import '../../core/design/palette.dart';
import 'turn_controller.dart';

/// Copy, retry, and who answered — the row under a finished reply.
///
/// Always visible rather than revealed on hover: hover does not exist on the
/// device this is mostly used on, and a control that only appears to some of
/// your users is a control half of them will never find.
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
          _Action(
            icon: Icons.content_copy_rounded,
            tooltip: 'Copy',
            onTap: () => Clipboard.setData(ClipboardData(text: reply.text)),
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
