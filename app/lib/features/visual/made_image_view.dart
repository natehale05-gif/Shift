import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/metrics.dart';
import '../../core/design/palette.dart';
import '../../data/image_store.dart';

/// A picture, wherever it is shown.
///
/// Bytes are fetched by id rather than passed in, because a transcript is
/// rebuilt on every delta of a streaming reply and holding megabytes in the
/// widget tree would make each of those rebuilds carry them. The store's cache
/// answers synchronously once it has them, so the common case draws with no
/// future at all — a `FutureBuilder` on every rebuild would flash empty each
/// time a neighbouring reply changed.
class MadeImageView extends StatefulWidget {
  final String id;

  /// What it was asked to be. Becomes the semantic label, because a picture
  /// with no alternative text is invisible to anyone using a screen reader —
  /// and this app knows exactly what the picture was meant to be.
  final String prompt;

  final VoidCallback? onTap;

  const MadeImageView({
    super.key,
    required this.id,
    this.prompt = '',
    this.onTap,
  });

  @override
  State<MadeImageView> createState() => _MadeImageViewState();
}

class _MadeImageViewState extends State<MadeImageView> {
  Uint8List? _bytes;
  bool _looked = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(MadeImageView old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id) {
      _bytes = null;
      _looked = false;
      _load();
    }
  }

  Future<void> _load() async {
    final store = context.read<ImageStore>();
    final held = store.cached(widget.id);
    if (held != null) {
      _bytes = held;
      _looked = true;
      return;
    }
    final loaded = await store.bytes(widget.id);
    if (!mounted) return;
    setState(() {
      _bytes = loaded;
      _looked = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bytes = _bytes;

    // Absent bytes with an index entry pointing at them is a real state — an
    // interrupted write, a cleared browser store — and it says so rather than
    // drawing a blank box that reads as a layout bug.
    if (bytes == null) {
      return AspectRatio(
        aspectRatio: 1,
        child: Container(
          decoration: BoxDecoration(
            color: c.surfaceSunken,
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(color: c.border),
          ),
          alignment: Alignment.center,
          child: _looked
              ? Text(
                  'This picture is no longer on this device.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: c.textFaint),
                )
              : const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
        ),
      );
    }

    final image = Semantics(
      image: true,
      label: widget.prompt.isEmpty ? 'A generated picture' : widget.prompt,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.md),
        // Contained, not cropped: a picture in a square frame that has been
        // cut to fit is a different picture, and the one thing someone judging
        // a generated image needs is all of it.
        child: Image.memory(bytes, fit: BoxFit.contain),
      ),
    );

    final tap = widget.onTap;
    if (tap == null) return image;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.md),
        onTap: tap,
        child: image,
      ),
    );
  }
}
