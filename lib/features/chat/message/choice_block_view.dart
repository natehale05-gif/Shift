import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tap_targets.dart';
import '../../../data/models/message_block.dart';
import '../../../data/stores/conversation_store.dart';

/// A question the assistant asked, as tappable options.
///
/// Replaces asking in prose and waiting for the answer to be typed. The
/// options are the same words the reply would have listed, so nothing is lost
/// by tapping instead — and on a phone it is the difference between one tap
/// and opening the keyboard.
///
/// Once answered it stays on screen, disabled, showing what was picked. The
/// alternative — removing it, or leaving it live — either erases the question
/// the answer belongs to or invites answering it twice.
class ChoiceBlockView extends StatefulWidget {
  final ChoiceBlock block;
  final String messageId;

  const ChoiceBlockView({
    super.key,
    required this.block,
    required this.messageId,
  });

  @override
  State<ChoiceBlockView> createState() => _ChoiceBlockViewState();
}

class _ChoiceBlockViewState extends State<ChoiceBlockView> {
  /// Local until sent, for the multi-select case where the answer is only
  /// complete once the user says so.
  late final Set<String> _picked = {...widget.block.chosen};
  bool _sending = false;

  bool get _locked => widget.block.answered || _sending;

  void _send(List<String> picked) {
    if (_locked || picked.isEmpty) return;
    setState(() {
      _sending = true;
      // A single-select pick never went through the toggle, so mark it here
      // too — otherwise the answered block shows no sign of which option was
      // chosen, which is the one thing it is left on screen to say.
      _picked
        ..clear()
        ..addAll(picked);
    });
    context.read<ConversationStore>().answerChoice(
          messageId: widget.messageId,
          blockId: widget.block.id,
          chosen: picked,
        );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppSemanticColors>()!;
    final block = widget.block;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            block.question,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final option in block.options)
                _OptionChip(
                  label: option,
                  selected: _picked.contains(option),
                  enabled: !_locked,
                  onTap: () {
                    if (block.multiSelect) {
                      setState(() => _picked.contains(option)
                          ? _picked.remove(option)
                          : _picked.add(option));
                    } else {
                      _send([option]);
                    }
                  },
                ),
            ],
          ),
          // Only multi-select needs a commit step. A single choice is complete
          // the moment it is tapped, and asking to confirm it would be a
          // second tap for nothing.
          if (block.multiSelect && !_locked) ...[
            const SizedBox(height: AppSpacing.sm),
            FilledButton(
              onPressed:
                  _picked.isEmpty ? null : () => _send(_picked.toList()),
              child: const Text('Send'),
            ),
          ],
        ],
      ),
    );
  }
}

class _OptionChip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _OptionChip({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppSemanticColors>()!;
    return ConstrainedBox(
      // Apple's minimum. These are the most-tapped thing in a turn that offers
      // them, so they are held to it explicitly rather than inheriting
      // whatever the chip theme happens to give.
      constraints: const BoxConstraints(
        minHeight: kMinTouchTarget,
        minWidth: kMinTouchTarget,
      ),
      child: Material(
        color: selected
            ? theme.colorScheme.primary.withValues(alpha: 0.14)
            : colors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (selected) ...[
                  Icon(Icons.check_rounded,
                      size: 16, color: theme.colorScheme.primary),
                  const SizedBox(width: AppSpacing.xs),
                ],
                Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: enabled || selected
                        ? theme.textTheme.bodyMedium?.color
                        : colors.textSecondary,
                    fontWeight: selected ? FontWeight.w600 : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
