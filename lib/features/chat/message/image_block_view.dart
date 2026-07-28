
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../data/models/message_block.dart';
import '../../../core/platform/download_service.dart';
import '../../../data/stores/conversation_store.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';

/// Claude-style message layout: user turns are compact right-aligned bubbles;
/// assistant turns are open prose — an ordered sequence of thinking, tool,
/// text, image, and artifact blocks — with a hover action row underneath.
class ImageBlockView extends StatelessWidget {
  final ImageBlock block;

  const ImageBlockView({super.key, required this.block});

  Widget _image(Uint8List bytes) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Image.memory(bytes, fit: BoxFit.contain),
            ),
          ),
          TextButton.icon(
            onPressed: () => DownloadService.downloadBytes(
              bytes,
              '${DownloadService.slugify(block.alt, fallback: 'image')}.png',
              mimeType: 'image/png',
            ),
            icon: const Icon(Icons.download_rounded, size: 16),
            label: const Text('Download'),
          ),
        ],
      );

  Widget _placeholder(BuildContext context, String label) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppSemanticColors>()!;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.image_not_supported_outlined,
              size: 16, color: colors.textSecondary),
          const SizedBox(width: 8),
          Text(label, style: theme.textTheme.labelMedium),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (block.pngBytes != null) return _image(block.pngBytes!);

    if (block.assetId != null) {
      // Reloaded session: bytes live in the IndexedDB asset store.
      return FutureBuilder<Uint8List?>(
        future:
            context.read<ConversationStore>().persistence.loadAsset(block.assetId!),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const SizedBox(
              height: 48,
              width: 48,
              child: Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 1.6),
                ),
              ),
            );
          }
          final bytes = snapshot.data;
          return bytes != null
              ? _image(bytes)
              : _placeholder(
                  context, 'Image no longer stored — ${block.alt}');
        },
      );
    }

    return _placeholder(context, 'Image not saved — ${block.alt}');
  }
}

/// Follow-up suggestion chips under the last completed reply — tap to send
/// (Claude's suggested follow-ups). Generic in demo mode.
