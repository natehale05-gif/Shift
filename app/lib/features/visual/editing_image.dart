import 'package:flutter/material.dart';

import '../../core/design/metrics.dart';
import '../../core/design/palette.dart';
import 'made_image_view.dart';

/// The picture the next message will change.
///
/// Shown rather than assumed, because the difference between "make a new one"
/// and "change that one" is invisible otherwise — and the second spends the
/// same money on a different outcome.
///
/// Its own file because both composers need it. Built for Visual first and
/// left there, which made *where you opened a picture from* decide whether you
/// could change it — an asymmetry with no reason behind it beyond which widget
/// happened to own the chip.
class EditingImage extends StatelessWidget {
  final String id;
  final VoidCallback onCancel;

  const EditingImage({super.key, required this.id, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            height: 34,
            child: MadeImageView(id: id, fit: BoxFit.cover),
          ),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Text(
              'Changing this picture',
              style: text.bodySmall?.copyWith(color: c.textMuted),
            ),
          ),
          IconButton(
            onPressed: onCancel,
            icon: const Icon(Icons.close_rounded, size: 16),
            tooltip: 'Make a new one instead',
            constraints: const BoxConstraints(
              minWidth: kMinTouchTarget,
              minHeight: kMinTouchTarget,
            ),
          ),
        ],
      ),
    );
  }
}
