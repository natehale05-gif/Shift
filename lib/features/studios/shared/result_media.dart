

/// Helpers shared by the image and video result views.
///
/// They were top-level functions inside the old 957-line studio_result_card,
/// where "shared between two views" was implicit. Splitting the file made the
/// sharing explicit — and Dart's per-library privacy meant they could not stay
/// private once the two views moved into separate folders.

import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

double aspectRatioValue(String label) {
  return switch (label) {
    '1:1' => 1,
    '4:5' => 4 / 5,
    '16:9' => 16 / 9,
    '9:16' => 9 / 16,
    _ => 1,
  };
}

/// Rasterizes whatever is painted inside the [RepaintBoundary] at [key] to
/// PNG bytes, for the "download image/thumbnail" actions.
Future<Uint8List?> capturePng(GlobalKey key, {double pixelRatio = 2}) async {
  final renderObject = key.currentContext?.findRenderObject();
  if (renderObject is! RenderRepaintBoundary) return null;
  final image = await renderObject.toImage(pixelRatio: pixelRatio);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  return byteData?.buffer.asUint8List();
}
