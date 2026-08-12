import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/metrics.dart';
import '../../core/design/palette.dart';
import '../../core/design/typography.dart';
import '../../core/platform/pick_image.dart';
import '../../data/image_store.dart';
import '../../data/made_image.dart';
import '../chat/composer.dart';
import '../chat/failure_card.dart';
import '../chat/turn_controller.dart';
import 'visual_turns.dart';
import '../../shell/mode.dart';
import 'editing_image.dart';
import 'image_viewer.dart';
import 'made_image_view.dart';

/// Visual mode: everything you have made, and a box to make another.
///
/// The gallery is the surface, in the same way the list is Notes' surface.
/// There is no album tree and no tagging, because neither earns its place
/// until there are enough pictures for the grid to stop working — and a
/// hierarchy built before then is one more thing to navigate for nothing.
///
/// A mode is a workspace and not a router, so the composer here is the
/// ordinary one: type a page request into it and you get a page. What Visual
/// changes is the *default* — a bare description makes a picture instead of
/// prose, which is the only reason to stand here rather than in Chat.
class VisualSurface extends StatelessWidget {
  const VisualSurface({super.key});

  @override
  Widget build(BuildContext context) {
    final images = context.watch<ImageStore>();
    final turn = context.watch<VisualTurns>();

    return Column(
      children: [
        Expanded(
          child: images.index.isEmpty
              ? const _NothingYet()
              : _Gallery(images: images.index),
        ),
        // The one thing this surface owes that the gallery cannot show. A
        // generation that failed has its sentence in a transcript nobody is
        // looking at, so without this a picture that never arrives looks like
        // a button that did nothing.
        if (turn.items.whereType<Reply>().lastOrNull
            case final Reply reply when reply.failure != null && !turn.running)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, 0),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: FailureCard(reply: reply),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
              Space.lg, Space.sm, Space.lg, Space.lg),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Composer(
                hint: turn.editingImage == null
                    ? 'Describe a picture'
                    : 'Say what to change',
                attachments: turn.editingImage == null
                    ? null
                    : EditingImage(
                        id: turn.editingImage!,
                        onCancel: () => turn.editImage(null),
                      ),
                busy: turn.running,
                onStop: turn.stop,
                onSend: (text) => turn.send(text, mode: AppMode.visual),
                // The mode is an image editor, and one that can only open its
                // own output is half an editor: most of what people want to
                // change is a picture they already have.
                onAttach: () => attachOwnPicture(context),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Brings in a picture from the person's own files and selects it for
/// changing.
Future<void> attachOwnPicture(BuildContext context) async {
  final images = context.read<ImageStore>();
  final turn = context.read<VisualTurns>();
  final messenger = ScaffoldMessenger.of(context);

  final picked = await pickImage();
  if (picked.refused case final why?) {
    // Cancelling is silent — the person chose that. A refusal is not, or the
    // picker simply closing reads as the app being broken.
    messenger.showSnackBar(SnackBar(content: Text(why)));
    return;
  }
  final image = picked.image;
  if (image == null) return;

  final id = 'a${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
  await images.save(
    MadeImage(
      id: id,
      // The filename, because that is the name this picture already has and
      // the one the person recognises in a gallery.
      prompt: image.name,
      provider: '',
      model: '',
      mimeType: image.mimeType,
      createdAt: DateTime.now(),
      origin: ImageOrigin.attached,
    ),
    image.bytes,
  );
  turn.editImage(id);
}

class _NothingYet extends StatelessWidget {
  const _NothingYet();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(AppMode.visual.activeIcon, size: 30, color: c.accent),
            const SizedBox(height: Space.lg),
            Text(
              'Describe something and it gets made.',
              textAlign: TextAlign.center,
              style: ShiftType.proseStyle(c.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _Gallery extends StatelessWidget {
  final List<MadeImage> images;

  const _Gallery({required this.images});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Sized by how wide a tile should be rather than by a column count, so
        // the grid reads the same on a phone and on a wide window instead of
        // stretching four tiles across a desktop.
        final columns = (constraints.maxWidth / 260).floor().clamp(1, 6);
        return GridView.builder(
          padding: const EdgeInsets.all(Space.lg),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: Space.md,
            mainAxisSpacing: Space.md,
          ),
          itemCount: images.length,
          itemBuilder: (context, i) => _Tile(image: images[i]),
        );
      },
    );
  }
}

class _Tile extends StatelessWidget {
  final MadeImage image;

  const _Tile({required this.image});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Container(
      decoration: BoxDecoration(
        color: c.surfaceSunken,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          MadeImageView(
            id: image.id,
            prompt: image.prompt,
            fit: BoxFit.cover,
            onTap: () => showImageViewer(
              context,
              image.id,
              turns: context.read<VisualTurns>(),
            ),
          ),
          // The prompt over the foot of the tile, on a scrim so it is legible
          // whatever the picture underneath is doing. Without it a grid of
          // pictures is unsearchable by eye — every one of them is "an image".
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.66),
                      Colors.black.withValues(alpha: 0),
                    ],
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(
                    Space.sm, Space.lg, Space.sm, Space.sm),
                child: Row(
                  children: [
                    // A small mark rather than a word: it says "you brought
                    // this one" without spending a line of the caption, which
                    // is the only place the picture's name fits.
                    if (image.origin == ImageOrigin.attached) ...[
                      const Icon(Icons.attach_file_rounded,
                          size: 12, color: Colors.white70),
                      const SizedBox(width: Space.xxs),
                    ],
                    Expanded(
                      child: Text(
                        image.prompt,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
