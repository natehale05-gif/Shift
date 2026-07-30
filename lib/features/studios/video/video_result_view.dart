


/// Renders a mock studio result inline in the chat. Every visual/audio/video
/// artifact here is procedurally generated at render time — nothing is a
/// real diffusion/video model output. Audio is a real (synthesized) WAV file
/// so playback and download both work; images/video download a real PNG
/// snapshot of the rendered art/thumbnail.
library;

import '../../../core/theme/app_spacing.dart';
import '../../../data/models/studio_result.dart';
import '../../../core/platform/download_service.dart';
import '../../../core/platform/open_url.dart';
import '../media/procedural_art.dart';
import '../media/procedural_painters.dart';
import '../shared/result_media.dart';
import '../shared/result_shell.dart';
import '../shared/round_icon_button.dart';
import '../shared/studio_badge.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../data/stores/conversation_store.dart';

class VideoResultView extends StatefulWidget {
  final VideoResult result;
  const VideoResultView({super.key, required this.result});

  @override
  State<VideoResultView> createState() => _VideoResultViewState();
}


class _VideoResultViewState extends State<VideoResultView> {
  final _boundaryKey = GlobalKey();
  Timer? _timer;
  double _progress = 0;
  bool _playing = false;
  bool _downloading = false;

  void _togglePlay() {
    if (_playing) {
      _timer?.cancel();
      setState(() => _playing = false);
      return;
    }
    setState(() {
      _playing = true;
      if (_progress >= 1) _progress = 0;
    });
    const tick = Duration(milliseconds: 100);
    _timer = Timer.periodic(tick, (t) {
      setState(() {
        _progress += tick.inMilliseconds / (widget.result.durationSec * 1000);
        if (_progress >= 1) {
          _progress = 1;
          _playing = false;
          t.cancel();
        }
      });
    });
  }

  Future<void> _download() async {
    setState(() => _downloading = true);
    final bytes = await capturePng(_boundaryKey);
    if (mounted) setState(() => _downloading = false);
    if (bytes == null) return;
    final filename = '${DownloadService.slugify(widget.result.prompt, fallback: 'video')}_thumbnail.png';
    DownloadService.downloadBytes(bytes, filename, mimeType: 'image/png');
  }

  /// Saves the rendered clip. The bytes are in memory on the turn that made
  /// it and in the asset store afterwards, so both are tried.
  Future<void> _saveVideo() async {
    final result = widget.result;
    var bytes = result.videoBytes;
    final assetId = result.videoAssetId;
    if (bytes == null && assetId != null && mounted) {
      bytes = await context.read<ConversationStore>().persistence
          .loadAsset(assetId);
    }
    if (bytes == null) return;
    await DownloadService.downloadBytes(
      bytes,
      '${DownloadService.slugify(result.prompt, fallback: 'video')}.mp4',
      mimeType: 'video/mp4',
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    final isReal = result.isRealVideo;
    return ResultShell(
      child: AspectRatio(
        aspectRatio: aspectRatioValue(result.aspectRatio),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Real renders (Heygen) show the provider thumbnail as the poster;
            // simulated ones paint the procedural gradient.
            RepaintBoundary(
              key: _boundaryKey,
              child: result.posterUrl != null
                  ? Image.network(
                      result.posterUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => CustomPaint(
                        painter: GradientArtPainter(
                          seed: result.seed,
                          palette: paletteFromSeed(result.seed),
                        ),
                      ),
                    )
                  : CustomPaint(
                      painter: GradientArtPainter(
                        seed: result.seed,
                        palette: paletteFromSeed(result.seed),
                      ),
                    ),
            ),
            Positioned(
              left: AppSpacing.sm,
              top: AppSpacing.sm,
              child: StudioBadge(
                  text: isReal
                      ? (result.providerLabel ?? 'Video')
                      : '${result.durationSec}s${result.identityLock ? ' · locked' : ''}'),
            ),
            if (!isReal)
              Positioned(
                right: AppSpacing.sm,
                top: AppSpacing.sm,
                child: RoundIconButton(
                  icon: Icons.download_rounded,
                  tooltip: 'Download thumbnail (PNG)',
                  loading: _downloading,
                  onPressed: _download,
                ),
              ),
            if (result.videoUrl != null)
              // No in-app player — link out to the finished clip.
              Center(
                child: FilledButton.icon(
                  onPressed: () => openUrl(result.videoUrl!),
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: Text('Open in ${result.providerLabel ?? 'browser'}'),
                ),
              )
            else if (isReal)
              // A provider that returns bytes rather than a hosted URL — its
              // content endpoint needs the API key, so there is nothing a
              // player or a link could point at. Save it instead.
              Center(
                child: FilledButton.icon(
                  onPressed: _saveVideo,
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: const Text('Save video (MP4)'),
                ),
              )
            else ...[
              Center(
                child: IconButton.filled(
                  onPressed: _togglePlay,
                  icon: Icon(
                      _playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: LinearProgressIndicator(
                  value: _progress,
                  minHeight: 3,
                  backgroundColor: Colors.white24,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
