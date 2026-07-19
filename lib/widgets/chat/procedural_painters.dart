import 'dart:math';
import 'package:flutter/material.dart';

/// Paints a seeded abstract gradient composition standing in for a real
/// diffusion-model image. Fully procedural — no network image, no bundled
/// stock asset, no licensing concerns.
class GradientArtPainter extends CustomPainter {
  final int seed;
  final List<Color> palette;

  GradientArtPainter({required this.seed, required this.palette});

  @override
  void paint(Canvas canvas, Size size) {
    final random = Random(seed);
    final rect = Offset.zero & size;

    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette[0], palette[1 % palette.length]],
        ).createShader(rect),
    );

    for (var i = 0; i < 5; i++) {
      final color = palette[random.nextInt(palette.length)].withValues(alpha: 0.35);
      final center = Offset(
        random.nextDouble() * size.width,
        random.nextDouble() * size.height,
      );
      final radius = size.shortestSide * (0.2 + random.nextDouble() * 0.35);
      canvas.drawCircle(center, radius, Paint()..color = color);
    }
  }

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
