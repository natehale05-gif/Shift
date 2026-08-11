import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/design/metrics.dart';
import '../../core/platform/save_file.dart';
import '../../data/image_store.dart';
import '../chat/turn_controller.dart';
import 'made_image_view.dart';

/// Opens one picture full-size, with the things you do to a picture.
///
/// A dialog rather than a route, so it works identically from the transcript
/// and from the gallery without either having to own a navigator entry.
///
/// [turns] is which conversation a "Change it" belongs to, and it is passed
/// rather than looked up because a lookup cannot answer it: both controllers
/// are provided for the whole app, so any precedence rule — Visual first, chat
/// first — is wrong in one of the two places. Written as a lookup first, and
/// the running app showed it immediately: pressing Change it in Chat handed
/// the picture to Visual's composer, where nobody was looking.
Future<void> showImageViewer(
  BuildContext context,
  String id, {
  TurnController? turns,
}) =>
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.82),
      builder: (_) => ImageViewer(id: id, turns: turns),
    );

class ImageViewer extends StatelessWidget {
  final String id;

  /// Where a "Change it" goes. Null means the surface that opened this has no
  /// composer to send it to, and the action is not offered rather than being
  /// offered and doing nothing.
  final TurnController? turns;

  const ImageViewer({super.key, required this.id, this.turns});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ImageStore>();
    final record = store.record(id);
    final prompt = record?.prompt ?? '';

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(Space.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(child: MadeImageView(id: id, prompt: prompt)),
          const SizedBox(height: Space.md),
          if (prompt.isNotEmpty) ...[
            // On the dark scrim, not on a surface — deliberately the only
            // place in the app that fixes a text colour, because the backdrop
            // here is dark in both themes.
            SelectableText(
              prompt,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Colors.white70),
            ),
            const SizedBox(height: Space.md),
          ],
          // A Wrap, not a Row. Five actions do not fit one line on a phone —
          // they overflowed by 27 pixels in an 800pt test window, so on a
          // 393pt screen the last two would simply have been unreachable.
          // The tap-target check could not see this: every control was the
          // right size and two of them were off the edge.
          Wrap(
            alignment: WrapAlignment.center,
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              _Action(
                icon: Icons.download_rounded,
                label: 'Save',
                onTap: () async {
                  final bytes = await store.bytes(id);
                  if (!context.mounted) return;
                  if (bytes == null) {
                    _say(context, 'Those bytes are no longer on this device.');
                    return;
                  }
                  final saved = await saveFile(
                    suggestedName: record?.filename ?? 'image.png',
                    bytes: bytes,
                    mimeType: record?.mimeType ?? 'image/png',
                  );
                  if (!context.mounted) return;
                  // Silent on a cancel: the person chose that, and telling
                  // them it did not save reads as a failure they caused.
                  if (saved) _say(context, 'Saved.');
                },
              ),
              // Editing is picked, not inferred. "Make it night" after four
              // pictures is genuinely ambiguous, and guessing wrong spends
              // money changing the wrong one while looking like it worked.
              //
              if (turns != null)
                _Action(
                  icon: Icons.auto_fix_high_rounded,
                  label: 'Change it',
                  onTap: () async {
                    turns!.editImage(id);
                    Navigator.of(context).pop();
                  },
                ),
              if (prompt.isNotEmpty)
                _Action(
                  icon: Icons.copy_rounded,
                  label: 'Copy prompt',
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: prompt));
                    if (context.mounted) _say(context, 'Prompt copied.');
                  },
                ),
              // Deletable, for the same reason chats and notes are: a mode
              // built to make things you would not want kept is not private
              // if the only way out is erasing the whole app.
              if (record != null)
                _Action(
                  icon: Icons.delete_outline_rounded,
                  label: 'Delete',
                  onTap: () async {
                    if (!await confirmDeleteImage(context, prompt)) return;
                    await store.remove(id);
                    if (context.mounted) Navigator.of(context).pop();
                  },
                ),
              _Action(
                icon: Icons.close_rounded,
                label: 'Close',
                onTap: () async => Navigator.of(context).pop(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _say(BuildContext context, String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
}

/// Asks first. No trash and no undo, so a mis-tap is the picture.
Future<bool> confirmDeleteImage(BuildContext context, String prompt) async {
  final answer = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete this picture?'),
      content: Text(
        prompt.isEmpty
            ? 'It will be removed from this device. This cannot be undone.'
            : '"$prompt" will be removed from this device. This cannot be '
                'undone.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return answer ?? false;
}

class _Action extends StatelessWidget {
  final IconData icon;
  final String label;
  final Future<void> Function() onTap;

  const _Action({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Radii.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.md),
          onTap: onTap,
          child: Container(
            // The viewer sits over a dark scrim where a mis-tap closes the
            // dialog, so these are given the full target rather than the
            // material default of 40.
            constraints: const BoxConstraints(
              minHeight: kMinTouchTarget,
              minWidth: kMinTouchTarget,
            ),
            padding: const EdgeInsets.symmetric(horizontal: Space.md),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: Colors.white),
                const SizedBox(width: Space.xs),
                Text(
                  label,
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      );
  }
}
