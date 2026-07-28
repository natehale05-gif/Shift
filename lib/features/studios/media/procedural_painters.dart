

/// Paints a seeded abstract gradient composition standing in for a real
/// diffusion-model image. Fully procedural — no network image, no bundled
/// stock asset, no licensing concerns.
library;
import 'dart:math';
import 'package:flutter/material.dart';
import 'procedural_art.dart';

class GradientArtPainter extends CustomPainter {
  final int seed;
  final List<Color> palette;

  GradientArtPainter({required this.seed, required this.palette});

  @override
  void paint(Canvas canvas, Size size) =>
      paintGradientArt(canvas, size, seed: seed, palette: palette);

  @override
  bool shouldRepaint(covariant GradientArtPainter oldDelegate) =>
      oldDelegate.seed != seed;
}

/// Paints a seeded fake waveform, optionally filled up to [progress] (0..1)
/// to show playback position.
class WaveformPainter extends CustomPainter {
  final int seed;
  final double progress;
  final Color color;
  final Color playedColor;

  WaveformPainter({
    required this.seed,
    required this.progress,
    required this.color,
    required this.playedColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final random = Random(seed);
    const barCount = 48;
    final barWidth = size.width / (barCount * 1.6);
    final gap = barWidth * 0.6;
    var x = 0.0;
    final amplitudes = List.generate(
      barCount,
      (_) => 0.15 + random.nextDouble() * 0.85,
    );

    for (var i = 0; i < barCount; i++) {
      final amplitude = amplitudes[i];
      final barHeight = size.height * amplitude;
      final isPlayed = i / barCount <= progress;
      final paint = Paint()..color = isPlayed ? playedColor : color;
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(x + barWidth / 2, size.height / 2),
          width: barWidth,
          height: barHeight,
        ),
        Radius.circular(barWidth / 2),
      );
      canvas.drawRRect(rect, paint);
      x += barWidth + gap;
    }
  }

  @override
  bool shouldRepaint(covariant WaveformPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.seed != seed;
}
