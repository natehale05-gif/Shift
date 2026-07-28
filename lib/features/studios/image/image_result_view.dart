


/// Renders a mock studio result inline in the chat. Every visual/audio/video
/// artifact here is procedurally generated at render time — nothing is a
/// real diffusion/video model output. Audio is a real (synthesized) WAV file
/// so playback and download both work; images/video download a real PNG
/// snapshot of the rendered art/thumbnail.

import '../../../core/theme/app_spacing.dart';
import '../../../data/models/studio_result.dart';
import '../../../core/platform/download_service.dart';
import '../media/procedural_art.dart';
import '../media/procedural_painters.dart';
import '../shared/result_media.dart';
import '../shared/result_shell.dart';
import '../shared/round_icon_button.dart';
import '../shared/studio_badge.dart';
import 'dart:async';
import 'package:flutter/material.dart';

class ImageResultView extends StatefulWidget {
  final ImageResult result;
  const ImageResultView({super.key, required this.result});

  @override
  State<ImageResultView> createState() => _ImageResultViewState();
}


class _ImageResultViewState extends State<ImageResultView> {
  final _boundaryKey = GlobalKey();
  bool _downloading = false;

  Future<void> _download() async {
    setState(() => _downloading = true);
    final bytes = await capturePng(_boundaryKey);
    if (mounted) setState(() => _downloading = false);
    if (bytes == null) return;
    final filename = '${DownloadService.slugify(widget.result.prompt, fallback: 'image')}.png';
    DownloadService.downloadBytes(bytes, filename, mimeType: 'image/png');
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    return ResultShell(
      child: AspectRatio(
        aspectRatio: aspectRatioValue(result.aspectRatio),
        child: Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(
              key: _boundaryKey,
              child: CustomPaint(
                painter: GradientArtPainter(
                  seed: result.seed,
                  palette: paletteFromSeed(result.seed),
                ),
              ),
            ),
            Positioned(
              left: AppSpacing.sm,
              bottom: AppSpacing.sm,
              child: StudioBadge(text: '${result.stylePreset} · ${result.aspectRatio}'),
            ),
            Positioned(
              right: AppSpacing.sm,
              top: AppSpacing.sm,
              child: RoundIconButton(
                icon: Icons.download_rounded,
                tooltip: 'Download PNG',
                loading: _downloading,
                onPressed: _download,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
