import 'package:flutter/material.dart';

import '../../core/design/metrics.dart';
import '../../core/design/palette.dart';
import '../../data/artifact.dart';

/// The deliverable's place in the conversation.
///
/// The page itself lives in the panel; this is the row that says it was made
/// and gets you back to it. Without it, closing the panel would put an artifact
/// permanently out of reach — the transcript would say "here's your page" with
/// no page and no way to ask for it again.
class ArtifactCard extends StatelessWidget {
  final Artifact artifact;
  final VoidCallback onOpen;

  const ArtifactCard({
    super.key,
    required this.artifact,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.md),
        onTap: onOpen,
        child: Container(
          constraints: const BoxConstraints(minHeight: kMinTouchTarget),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(color: c.border),
          ),
          padding: const EdgeInsets.symmetric(
              horizontal: Space.md, vertical: Space.sm),
          child: Row(
            children: [
              Icon(
                artifact.previewable
                    ? Icons.article_outlined
                    : Icons.code_rounded,
                size: 18,
                color: c.accent,
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      artifact.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleMedium?.copyWith(color: c.text),
                    ),
                    Text(
                      // The version count only when there is one worth
                      // mentioning — "1 version" is noise on every card.
                      artifact.versions.length > 1
                          ? '${artifact.language ?? artifact.kind.name} · '
                              '${artifact.versions.length} versions'
                          : artifact.language ?? artifact.kind.name,
                      style: text.labelSmall?.copyWith(color: c.textFaint),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 18, color: c.textFaint),
            ],
          ),
        ),
      ),
    );
  }
}
