


import '../../../core/theme/app_colors.dart';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

const proceduralArtPalette = [
  AppColors.accent,
  AppColors.systemPink,
  AppColors.systemBlue,
  AppColors.systemGreen,
  AppColors.systemOrange,
  AppColors.systemPurple,
];

List<Color> paletteFromSeed(int seed) {
  final start = seed % proceduralArtPalette.length;
  return [
    proceduralArtPalette[start],
    proceduralArtPalette[(start + 2) % proceduralArtPalette.length],
    proceduralArtPalette[(start + 4) % proceduralArtPalette.length],
  ];
}

/// The actual "image" a studio prompt maps to: a seeded abstract gradient
/// composition standing in for a real diffusion-model output. Shared by the
/// live [GradientArtPainter] (the inline chat card) and [rasterizeGradientArt]
/// below, so both draw exactly the same picture for a given seed.
void paintGradientArt(
  Canvas canvas,
  Size size, {
  required int seed,
  required List<Color> palette,
}) {
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

/// Rasterizes [paintGradientArt] headlessly — no widget tree or mounted
/// [RepaintBoundary] required — to real PNG bytes. This is how the mock
/// "image generation" produces bytes that can be embedded somewhere other
/// than an inline chat card, e.g. spliced into an HTML artifact.
Future<Uint8List> rasterizeGradientArt({required int seed, int size = 768}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  paintGradientArt(
    canvas,
    Size(size.toDouble(), size.toDouble()),
    seed: seed,
    palette: paletteFromSeed(seed),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(size, size);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  return byteData!.buffer.asUint8List();
}
