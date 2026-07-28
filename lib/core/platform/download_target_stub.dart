import 'dart:typed_data';

/// Inert stand-in used only when compiling for non-web targets (e.g.
/// `flutter test`'s VM). This app ships exclusively to web, so this is
/// never exercised at runtime — it exists purely so pure-logic code that
/// touches [DownloadService] keeps compiling/running under `flutter test`.
void triggerDownload(Uint8List bytes, String filename, String mimeType) {}
