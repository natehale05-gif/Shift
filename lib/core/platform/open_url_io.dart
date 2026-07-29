import 'package:url_launcher/url_launcher.dart';

/// Hands the URL to the OS — the system browser, mail client, or whatever is
/// registered for the scheme. Fire-and-forget to keep the signature the same
/// as the browser's `window.open`, which callers already treat as synchronous.
void openUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  launchUrl(uri, mode: LaunchMode.externalApplication);
}
