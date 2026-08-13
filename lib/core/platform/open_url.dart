import 'package:url_launcher/url_launcher.dart';

/// Opens [url] outside the app — a browser, or whatever the OS has registered
/// for the scheme.
///
/// **One file, not a conditional pair.** Every other shim in this directory
/// has one because the two arms genuinely differ; `url_launcher` already
/// resolves an implementation for all six targets, including web, so a pair
/// here would be two files calling the same function.
///
/// Used for three things, and each of them is a place the app hands over
/// rather than pretends: the release page when an update cannot be installed
/// from inside the app, a downloaded `.dmg` for Finder to mount, and a source
/// link in a reply.
///
/// Never throws. A launcher that refuses — no browser registered, a scheme the
/// OS does not know, a sandbox that forbids it — is a thing the caller cannot
/// fix and the reader cannot act on, so it returns false and the caller says
/// what it was trying to open.
Future<bool> openUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}
