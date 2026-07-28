import 'dart:convert';
import 'dart:typed_data';

import 'download_target_stub.dart' if (dart.library.html) 'download_target_web.dart' as target;

/// Triggers a real browser file download — this app is web-only, so a
/// Blob + anchor-click (in `download_target_web.dart`) is the simplest
/// correct approach. The actual `dart:html` usage lives behind a
/// conditional import so pure-logic code that calls into this service
/// (e.g. [StudioResponseBank]) still compiles and runs under `flutter
/// test`'s VM target, which has no `dart:html`.
class DownloadService {
  DownloadService._();

  static void downloadBytes(
    Uint8List bytes,
    String filename, {
    String mimeType = 'application/octet-stream',
  }) {
    target.triggerDownload(bytes, filename, mimeType);
  }

  static void downloadText(
    String text,
    String filename, {
    String mimeType = 'text/plain;charset=utf-8',
  }) {
    downloadBytes(Uint8List.fromList(utf8.encode(text)), filename, mimeType: mimeType);
  }

  /// lower_snake_case filename stem derived from free text.
  static String slugify(String input, {String fallback = 'file'}) {
    final words = input
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(6)
        .toList();
    return words.isEmpty ? fallback : words.join('_');
  }
}
