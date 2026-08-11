import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

/// Off-web: a save dialog, then the bytes.
///
/// `file_selector` resolves on Linux, macOS and Windows — the three targets
/// with a file manager to save into. On iOS and Android it does not, so the
/// dialog never opens and this reports `false`; the sharing route those two
/// platforms actually want is its own piece of work rather than a dialog
/// pretending to be one.
Future<bool> saveFile({
  required String suggestedName,
  required Uint8List bytes,
  String mimeType = 'application/octet-stream',
}) async {
  try {
    final location = await getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: [
        XTypeGroup(
          label: mimeType,
          extensions: [
            if (suggestedName.contains('.')) suggestedName.split('.').last,
          ],
        ),
      ],
    );
    // Cancelled. Not a failure — reported as "nothing was saved", which is
    // exactly what the person asked for by pressing Cancel, so the caller
    // must not show an error.
    if (location == null) return false;

    await File(location.path).writeAsBytes(bytes, flush: true);
    return true;
  } catch (_) {
    return false;
  }
}
