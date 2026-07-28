// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Opens [url] in a new browser tab. Only compiled in for web (selected via
/// the conditional import in open_url.dart).
void openUrl(String url) {
  html.window.open(url, '_blank');
}
