


/// Renders a mock studio result inline in the chat. Every visual/audio/video
/// artifact here is procedurally generated at render time — nothing is a
/// real diffusion/video model output. Audio is a real (synthesized) WAV file
/// so playback and download both work; images/video download a real PNG
/// snapshot of the rendered art/thumbnail.
library;

import '../../../core/theme/app_spacing.dart';
import '../../../data/models/studio_result.dart';
import '../../../core/platform/download_service.dart';
import '../shared/result_shell.dart';
import '../shared/studio_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TranslateResultView extends StatelessWidget {
  final TranslateResult result;
  const TranslateResultView({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                        ? 'Translated · ${result.targetLanguage}'
                        : 'Simulated · ${result.targetLanguage}'),
                const Spacer(),
                IconButton(
                  tooltip: 'Copy translation',
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  onPressed: () {
                    Clipboard.setData(
                        ClipboardData(text: result.translatedText));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Copied to clipboard')),
                    );
                  },
                ),
                IconButton(
                  tooltip: 'Download as .txt',
                  icon: const Icon(Icons.download_rounded, size: 18),
                  onPressed: () {
                    final filename =
                        '${DownloadService.slugify('translation ${result.targetLanguage}', fallback: 'translation')}.txt';
                    DownloadService.downloadText(result.translatedText, filename);
                  },
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(result.translatedText, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
