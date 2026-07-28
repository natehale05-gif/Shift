
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/models/message_block.dart';
import '../../../services/download_service.dart';
import '../../../data/stores/conversation_store.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../artifacts/artifact_preview.dart';

/// Claude-style message layout: user turns are compact right-aligned bubbles;
/// assistant turns are open prose — an ordered sequence of thinking, tool,
/// text, image, and artifact blocks — with a hover action row underneath.
import 'artifact_card.dart';

class InlineArtifact extends StatelessWidget {
  final ArtifactRefBlock block;

  const InlineArtifact({super.key, required this.block});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppSemanticColors>()!;
    final artifact =
        context.watch<ConversationStore>().current?.artifactById(block.artifactId);
    if (artifact == null) {
      // Artifact pruned or from another conversation — degrade to a card.
      return ArtifactCard(block: block, onOpen: null);
    }
    final versionIndex =
        block.versionIndex.clamp(0, artifact.versions.length - 1);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 680),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 540,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border.all(color: colors.border),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: ArtifactPreview(
              artifact: artifact,
              versionIndex: versionIndex,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: TextButton.icon(
              onPressed: () => DownloadService.downloadText(
                artifact.versions[versionIndex].content,
                '${DownloadService.slugify(artifact.title)}.html',
              ),
              icon: const Icon(Icons.download_rounded, size: 16),
              label: const Text('Download'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tappable card representing an artifact created/updated by this turn.
