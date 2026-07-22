// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:html' as html;
import 'dart:js_util' as js_util;

/// Renders [htmlDoc] in a hidden iframe and opens the browser print dialog, so
/// the user can Save as PDF. Dependency-free and CDN-free — the local stand-in
/// for a PDF export.
void printHtmlDocument(String htmlDoc) {
  final iframe = html.IFrameElement()
    ..style.position = 'fixed'
    ..style.right = '0'
    ..style.bottom = '0'
    ..style.width = '0'
    ..style.height = '0'
    ..style.border = '0';
  iframe.setAttribute('srcdoc', htmlDoc);

  iframe.onLoad.listen((_) {
    try {
      final win = js_util.getProperty(iframe, 'contentWindow');
      js_util.callMethod(win, 'focus', const []);
      js_util.callMethod(win, 'print', const []);
    } catch (_) {
      // Printing may be blocked; nothing else to do.
    }
    Timer(const Duration(seconds: 2), iframe.remove);
  });

  html.document.body!.append(iframe);
}
