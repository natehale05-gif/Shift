import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';

import '../../models/studio_result.dart';
import '../../services/audio_synth_service.dart';
import '../../services/download_service.dart';
import '../../services/open_url.dart';
import '../../services/procedural_art.dart';
import '../../services/web_audio_player.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';
import 'procedural_painters.dart';

/// Renders a mock studio result inline in the chat. Every visual/audio/video
/// artifact here is procedurally generated at render time — nothing is a
/// real diffusion/video model output. Audio is a real (synthesized) WAV file
/// so playback and download both work; images/video download a real PNG
/// snapshot of the rendered art/thumbnail.
class StudioResultCard extends StatelessWidget {
  final StudioResult result;

  const StudioResultCard({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    return switch (result) {
      ImageResult r => _ImageResultView(result: r),
      VideoResult r => _VideoResultView(result: r),
      AudioResult r => _AudioResultView(result: r),
      CopyResult r => _CopyResultView(result: r),
      CodeResult r => _CodeResultView(result: r),
    };
  }
}

double _aspectRatioValue(String label) {
  return switch (label) {
    '1:1' => 1,
    '4:5' => 4 / 5,
    '16:9' => 16 / 9,
    '9:16' => 9 / 16,
    _ => 1,
  };
}

/// Rasterizes whatever is painted inside the [RepaintBoundary] at [key] to
/// PNG bytes, for the "download image/thumbnail" actions below.
Future<Uint8List?> _capturePng(GlobalKey key, {double pixelRatio = 2}) async {
  final renderObject = key.currentContext?.findRenderObject();
  if (renderObject is! RenderRepaintBoundary) return null;
  final image = await renderObject.toImage(pixelRatio: pixelRatio);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  return byteData?.buffer.asUint8List();
}

class _ResultShell extends StatelessWidget {
  final Widget child;
  final Widget? footer;
  final double maxWidth;

  const _ResultShell({required this.child, this.footer, this.maxWidth = 320});

  @override
  Widget build(BuildContext context) {
    final border = Theme.of(context).extension<AppSemanticColors>()!.border;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            child,
            if (footer != null)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: footer,
              ),
          ],
        ),
      ),
    );
  }
}

class _ImageResultView extends StatefulWidget {
  final ImageResult result;
  const _ImageResultView({required this.result});

  @override
  State<_ImageResultView> createState() => _ImageResultViewState();
}

class _ImageResultViewState extends State<_ImageResultView> {
  final _boundaryKey = GlobalKey();
  bool _downloading = false;

  Future<void> _download() async {
    setState(() => _downloading = true);
    final bytes = await _capturePng(_boundaryKey);
    if (mounted) setState(() => _downloading = false);
    if (bytes == null) return;
    final filename = '${DownloadService.slugify(widget.result.prompt, fallback: 'image')}.png';
    DownloadService.downloadBytes(bytes, filename, mimeType: 'image/png');
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    return _ResultShell(
      child: AspectRatio(
        aspectRatio: _aspectRatioValue(result.aspectRatio),
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
              child: _Badge(text: '${result.stylePreset} · ${result.aspectRatio}'),
            ),
            Positioned(
              right: AppSpacing.sm,
              top: AppSpacing.sm,
              child: _RoundIconButton(
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

class _VideoResultView extends StatefulWidget {
  final VideoResult result;
  const _VideoResultView({required this.result});

  @override
  State<_VideoResultView> createState() => _VideoResultViewState();
}

class _VideoResultViewState extends State<_VideoResultView> {
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
    final bytes = await _capturePng(_boundaryKey);
    if (mounted) setState(() => _downloading = false);
    if (bytes == null) return;
    final filename = '${DownloadService.slugify(widget.result.prompt, fallback: 'video')}_thumbnail.png';
    DownloadService.downloadBytes(bytes, filename, mimeType: 'image/png');
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
    return _ResultShell(
      child: AspectRatio(
        aspectRatio: _aspectRatioValue(result.aspectRatio),
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
              child: _Badge(
                  text: isReal
                      ? (result.providerLabel ?? 'Video')
                      : '${result.durationSec}s${result.identityLock ? ' · locked' : ''}'),
            ),
            if (!isReal)
              Positioned(
                right: AppSpacing.sm,
                top: AppSpacing.sm,
                child: _RoundIconButton(
                  icon: Icons.download_rounded,
                  tooltip: 'Download thumbnail (PNG)',
                  loading: _downloading,
                  onPressed: _download,
                ),
              ),
            if (isReal)
              // No in-app player — link out to the finished clip.
              Center(
                child: FilledButton.icon(
                  onPressed: () => openUrl(result.videoUrl!),
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: Text('Open in ${result.providerLabel ?? 'browser'}'),
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

class _AudioResultView extends StatefulWidget {
  final AudioResult result;
  const _AudioResultView({required this.result});

  @override
  State<_AudioResultView> createState() => _AudioResultViewState();
}

class _AudioResultViewState extends State<_AudioResultView> {
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
    return _ResultShell(
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

class _CopyResultView extends StatelessWidget {
  final CopyResult result;
  const _CopyResultView({required this.result});

  @override
  Widget build(BuildContext context) {
    return _ResultShell(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _Badge(text: '${result.contentType} · ${result.tone}'),
                const Spacer(),
                IconButton(
                  tooltip: 'Copy to clipboard',
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: result.text));
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
                        '${DownloadService.slugify('${result.contentType} ${result.tone}', fallback: 'copy')}.txt';
                    DownloadService.downloadText(result.text, filename);
                  },
                ),
              ],
            ),
            Text(result.text, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

class _CodeResultView extends StatelessWidget {
  final CodeResult result;
  const _CodeResultView({required this.result});

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
    return _ResultShell(
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

class _Badge extends StatelessWidget {
  final String text;
  const _Badge({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final bool loading;
  final String? tooltip;

  const _RoundIconButton({
    required this.icon,
    required this.onPressed,
    this.loading = false,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final button = Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        shape: BoxShape.circle,
      ),
      child: loading
          ? const Padding(
              padding: EdgeInsets.all(8),
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
          : IconButton(
              padding: EdgeInsets.zero,
              iconSize: 16,
              icon: Icon(icon, color: Colors.white),
              onPressed: onPressed,
            ),
    );
    return tooltip != null ? Tooltip(message: tooltip!, child: button) : button;
  }
}
