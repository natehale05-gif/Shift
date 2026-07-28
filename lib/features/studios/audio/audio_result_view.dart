


/// Renders a mock studio result inline in the chat. Every visual/audio/video
/// artifact here is procedurally generated at render time — nothing is a
/// real diffusion/video model output. Audio is a real (synthesized) WAV file
/// so playback and download both work; images/video download a real PNG
/// snapshot of the rendered art/thumbnail.
library;

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/studio_result.dart';
import '../../../core/platform/download_service.dart';
import '../../../core/platform/web_audio_player.dart';
import '../media/audio_synth_service.dart';
import '../media/procedural_painters.dart';
import '../shared/result_shell.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AudioResultView extends StatefulWidget {
  final AudioResult result;
  const AudioResultView({super.key, required this.result});

  @override
  State<AudioResultView> createState() => _AudioResultViewState();
}


class _AudioResultViewState extends State<AudioResultView> {
  WebAudioPlayer? _player;
  double _progress = 0;
  bool _playing = false;
  bool _preparing = false;

  int get _bpm =>
      int.tryParse(RegExp(r'(\d+)\s*BPM').firstMatch(widget.result.subtitle)?.group(1) ?? '') ?? 100;

  Uint8List _synthesize() => AudioSynthService.synthesizeWav(
        seed: widget.result.seed,
        durationSec: widget.result.durationSec,
        bpm: _bpm,
        speechLike: widget.result.kind == AudioKind.voice,
      );

  void _ensurePlayer() {
    if (_player != null) return;
    final player = WebAudioPlayer.fromWav(_synthesize());
    player.onProgress.listen((_) {
      if (!mounted) return;
      setState(() => _progress = player.progress);
    });
    player.onEnded.listen((_) {
      if (!mounted) return;
      setState(() {
        _playing = false;
        _progress = 0;
      });
    });
    _player = player;
  }

  Future<void> _togglePlay() async {
    if (_playing) {
      _player?.pause();
      setState(() => _playing = false);
      return;
    }
    setState(() => _preparing = true);
    _ensurePlayer();
    if (_progress >= 1) _player!.restart();
    await _player!.play();
    if (!mounted) return;
    setState(() {
      _preparing = false;
      _playing = true;
    });
  }

  void _download() {
    final filename =
        '${DownloadService.slugify(widget.result.title, fallback: 'audio')}.wav';
    DownloadService.downloadBytes(_synthesize(), filename, mimeType: 'audio/wav');
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    final colors = Theme.of(context).extension<AppSemanticColors>()!;
    final accent = Theme.of(context).colorScheme.primary;
    return ResultShell(
      footer: result.transcript != null
          ? Text(
              result.transcript!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _preparing
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton.filled(
                    onPressed: _togglePlay,
                    icon: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                  ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    result.title,
                    style: Theme.of(context).textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    result.subtitle,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  SizedBox(
                    height: 32,
                    child: CustomPaint(
                      painter: WaveformPainter(
                        seed: result.seed,
                        progress: _progress,
                        color: colors.surfaceAlt,
                        playedColor: accent,
                      ),
                      size: Size.infinite,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Download WAV',
              icon: const Icon(Icons.download_rounded, size: 18),
              onPressed: _download,
            ),
          ],
        ),
      ),
    );
  }
}
