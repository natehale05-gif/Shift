import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';

/// Whether this platform can save a file at all.
///
/// `file_selector` resolves on the three desktops and nowhere else, so on iOS
/// and Android [saveFile] cannot open a dialog and returns false. A caller that
/// shows the control anyway ships a button that does nothing — which on a phone
/// is the only kind of button there is. Checked rather than attempted, so the
/// control is absent instead of dead.
///
/// The honest fix for those two is a share sheet, which is its own piece of
/// work and not a save dialog wearing a different name.
bool get canSaveFile =>
    const {TargetPlatform.linux, TargetPlatform.macOS, TargetPlatform.windows}
        .contains(defaultTargetPlatform);

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
