import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/studio_result.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';
import 'procedural_painters.dart';

/// Renders a mock studio result inline in the chat. Every visual/audio/video
/// artifact here is procedurally generated at render time — nothing is a
/// real diffusion/video/voice/music model output.
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
    };
  }
}

const _palette = [
  AppColors.accent,
  AppColors.systemPink,
  AppColors.systemBlue,
  AppColors.systemGreen,
  AppColors.systemOrange,
  AppColors.systemPurple,
];

List<Color> _paletteFromSeed(int seed) {
  final start = seed % _palette.length;
  return [
    _palette[start],
    _palette[(start + 2) % _palette.length],
    _palette[(start + 4) % _palette.length],
  ];
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

class _ResultShell extends StatelessWidget {
  final Widget child;
  final Widget? footer;

  const _ResultShell({required this.child, this.footer});

  @override
  Widget build(BuildContext context) {
    final border = Theme.of(context).extension<AppSemanticColors>()!.border;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
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

class _ImageResultView extends StatelessWidget {
  final ImageResult result;
  const _ImageResultView({required this.result});

  @override
  Widget build(BuildContext context) {
    return _ResultShell(
      child: AspectRatio(
        aspectRatio: _aspectRatioValue(result.aspectRatio),
        child: CustomPaint(
          painter: GradientArtPainter(
            seed: result.seed,
            palette: _paletteFromSeed(result.seed),
          ),
          child: Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: _Badge(text: '${result.stylePreset} · ${result.aspectRatio}'),
            ),
          ),
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
  Timer? _timer;
  double _progress = 0;
  bool _playing = false;

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

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
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
            CustomPaint(
              painter: GradientArtPainter(
                seed: result.seed,
                palette: _paletteFromSeed(result.seed),
              ),
            ),
            Positioned(
              left: AppSpacing.sm,
              top: AppSpacing.sm,
              child: _Badge(text: '${result.durationSec}s${result.identityLock ? ' · locked' : ''}'),
            ),
            Center(
              child: IconButton.filled(
                onPressed: _togglePlay,
                icon: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
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
  Timer? _timer;
  double _progress = 0;
  bool _playing = false;

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

  @override
  void dispose() {
    _timer?.cancel();
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
          children: [
            IconButton.filled(
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
              ],
            ),
            Text(result.text, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
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
