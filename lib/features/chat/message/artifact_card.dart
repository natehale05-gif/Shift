
import 'package:flutter/material.dart';

import '../../../data/models/artifact.dart';
import '../../../data/models/message_block.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';

/// Claude-style message layout: user turns are compact right-aligned bubbles;
/// assistant turns are open prose — an ordered sequence of thinking, tool,
/// text, image, and artifact blocks — with a hover action row underneath.
class ArtifactCard extends StatelessWidget {
  final ArtifactRefBlock block;
  final void Function(ArtifactRefBlock ref)? onOpen;

  const ArtifactCard({super.key, required this.block, this.onOpen});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppSemanticColors>()!;
    return InkWell(
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      onTap: onOpen != null ? () => onOpen!(block) : null,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              child: Icon(
                switch (block.kind) {
                  ArtifactKind.html => Icons.language_rounded,
                  ArtifactKind.svg => Icons.polyline_rounded,
                  ArtifactKind.markdown => Icons.article_outlined,
                  ArtifactKind.code => Icons.code_rounded,
                },
                size: 18,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    block.title,
                    style: theme.textTheme.titleSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'Artifact · v${block.versionIndex + 1}',
                    style: theme.textTheme.labelSmall,
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: colors.textSecondary),
          ],
        ),
      ),
    );
  }
}
