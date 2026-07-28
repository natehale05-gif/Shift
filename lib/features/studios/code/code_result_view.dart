


/// Renders a mock studio result inline in the chat. Every visual/audio/video
/// artifact here is procedurally generated at render time — nothing is a
/// real diffusion/video model output. Audio is a real (synthesized) WAV file
/// so playback and download both work; images/video download a real PNG
/// snapshot of the rendered art/thumbnail.

import '../../../core/theme/app_spacing.dart';
import '../../../data/models/studio_result.dart';
import '../../../core/platform/download_service.dart';
import '../shared/result_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';

class CodeResultView extends StatelessWidget {
  final CodeResult result;
  const CodeResultView({super.key, required this.result});

  static const _highlightLanguages = {
    'Python': 'python',
    'JavaScript': 'javascript',
    'TypeScript': 'typescript',
    'Dart': 'dart',
    'Swift': 'swift',
    'SQL': 'sql',
    'HTML': 'xml',
  };

  @override
  Widget build(BuildContext context) {
    final language = _highlightLanguages[result.language];
    return ResultShell(
      maxWidth: 480,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            color: const Color(0xFF282C34),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                const Icon(Icons.insert_drive_file_outlined, size: 14, color: Colors.white70),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    result.filename,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: 'Copy to clipboard',
                  icon: const Icon(Icons.copy_rounded, size: 16, color: Colors.white70),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: result.code));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Copied to clipboard')),
                    );
                  },
                ),
                IconButton(
                  tooltip: 'Download ${result.filename}',
                  icon: const Icon(Icons.download_rounded, size: 16, color: Colors.white70),
                  onPressed: () => DownloadService.downloadText(result.code, result.filename),
                ),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: SingleChildScrollView(
              child: HighlightView(
                result.code,
                language: language,
                theme: atomOneDarkTheme,
                padding: const EdgeInsets.all(AppSpacing.md),
                textStyle: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
