import 'dart:convert';
import 'dart:typed_data';

import 'download_target_io.dart'
    if (dart.library.html) 'download_target_web.dart' as target;

/// Saves a file to wherever "saving a file" means on this platform: a
/// Blob + anchor-click in the browser, a native save dialog everywhere else.
///
/// Asynchronous because it has to be. The browser can fire a download
/// synchronously, but a desktop save dialog cannot — and this used to be
/// `void`, which is why the desktop path could only ever be the no-op it was.
/// Callers are all button handlers, so awaiting costs them nothing.
class DownloadService {
  DownloadService._();

  /// Returns the path written on platforms that have one, or null on the web
  /// (the browser owns the destination) and when the user cancels the dialog.
  static Future<String?> downloadBytes(
    Uint8List bytes,
    String filename, {
    String mimeType = 'application/octet-stream',
  }) {
    return target.triggerDownload(bytes, filename, mimeType);
  }

  static Future<String?> downloadText(
    String text,
    String filename, {
    String mimeType = 'text/plain;charset=utf-8',
  }) {
    return downloadBytes(Uint8List.fromList(utf8.encode(text)), filename,
        mimeType: mimeType);
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
