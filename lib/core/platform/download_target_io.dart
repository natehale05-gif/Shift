import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

/// Desktop and Android: ask where to put it, then write the bytes.
///
/// `file_selector` already resolves an implementation for Android, Linux,
/// macOS and Windows, so this needs no new dependency — only the async seam
/// that [DownloadService] previously lacked.
///
/// Returns the path written, or null if the user dismissed the dialog.
Future<String?> triggerDownload(
    Uint8List bytes, String filename, String mimeType) async {
  final location = await getSaveLocation(
    suggestedName: filename,
    acceptedTypeGroups: [
      XTypeGroup(label: _labelFor(filename), extensions: [_extensionOf(filename)]),
    ],
  );
  if (location == null) return null;
  final file = File(location.path);
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

String _extensionOf(String filename) {
  final dot = filename.lastIndexOf('.');
  return dot == -1 ? '' : filename.substring(dot + 1);
}

String _labelFor(String filename) {
  final ext = _extensionOf(filename);
  return ext.isEmpty ? 'File' : ext.toUpperCase();
}
