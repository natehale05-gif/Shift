import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/design/metrics.dart';
import '../../core/platform/save_file.dart';
import '../../data/image_store.dart';
import 'made_image_view.dart';

/// Opens one picture full-size, with the things you do to a picture.
///
/// A dialog rather than a route, so it works identically from the transcript
/// and from the gallery without either having to own a navigator entry.
Future<void> showImageViewer(BuildContext context, String id) => showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.82),
      builder: (_) => ImageViewer(id: id),
    );

class ImageViewer extends StatelessWidget {
  final String id;

  const ImageViewer({super.key, required this.id});

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
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
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
              if (prompt.isNotEmpty)
                _Action(
                  icon: Icons.copy_rounded,
                  label: 'Copy prompt',
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: prompt));
                    if (context.mounted) _say(context, 'Prompt copied.');
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

class _Action extends StatelessWidget {
  final IconData icon;
  final String label;
  final Future<void> Function() onTap;

  const _Action({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.xs),
      child: Material(
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
      ),
    );
  }
}
