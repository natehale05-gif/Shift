


/// Renders a mock studio result inline in the chat. Every visual/audio/video
/// artifact here is procedurally generated at render time — nothing is a
/// real diffusion/video model output. Audio is a real (synthesized) WAV file
/// so playback and download both work; images/video download a real PNG
/// snapshot of the rendered art/thumbnail.

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/studio_result.dart';
import '../../../services/download_service.dart';
import '../shared/result_shell.dart';
import '../shared/studio_badge.dart';
import 'deck_pptx.dart';
import 'package:flutter/material.dart';

class DeckResultView extends StatelessWidget {
  final DeckResult result;
  const DeckResultView({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppSemanticColors>()!;
    return ResultShell(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                StudioBadge(
                    text: result.live
                        ? '${result.slides.length} slides'
                        : 'Draft · ${result.slides.length} slides'),
                const Spacer(),
                FilledButton.tonalIcon(
                  onPressed: () {
                    final bytes = DeckPptx.build(result);
                    final filename =
                        '${DownloadService.slugify(result.title, fallback: 'deck')}.pptx';
                    DownloadService.downloadBytes(bytes, filename,
                        mimeType:
                            'application/vnd.openxmlformats-officedocument.presentationml.presentation');
                  },
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: const Text('Download .pptx'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            // A compact outline preview of the slides.
            for (var i = 0; i < result.slides.length; i++) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 22,
                      alignment: Alignment.centerLeft,
                      child: Text('${i + 1}',
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: colors.textSecondary)),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(result.slides[i].title,
                              style: theme.textTheme.titleSmall),
                          if (result.slides[i].bullets.isNotEmpty)
                            Text(result.slides[i].bullets.join(' · '),
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: colors.textSecondary)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
