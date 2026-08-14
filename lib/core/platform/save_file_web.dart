import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Whether this platform can save a file at all. See the IO copy.
const bool canSaveFile = true;

/// The browser: an object URL and a click on an anchor nobody sees.
///
/// There is no save dialog to await and no path to report — the browser takes
/// it from here, and where it lands is the user's download setting. So `true`
/// means "handed to the browser", which is the strongest true statement
/// available on this platform, and the caller's copy says "Saved" rather than
/// naming a folder it cannot know.
Future<bool> saveFile({
  required String suggestedName,
  required Uint8List bytes,
  String mimeType = 'application/octet-stream',
}) async {
  String? url;
  try {
    final blob = web.Blob(
      [bytes.toJS].toJS,
      web.BlobPropertyBag(type: mimeType),
    );
    url = web.URL.createObjectURL(blob);

    final anchor = web.document.createElement('a') as web.HTMLAnchorElement
      ..href = url
      ..download = suggestedName
      ..style.display = 'none';
    web.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    return true;
  } catch (_) {
    return false;
  } finally {
    // Released whatever happened. An object URL holds the whole image alive
    // for the life of the document, so leaking one per download is a slow
    // memory leak in a tab people leave open all day.
    if (url != null) web.URL.revokeObjectURL(url);
  }
}
