// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:html' as html;

/// Fades out and removes the `#boot` splash that `web/index.html` paints before
/// Flutter is ready. Called once the first Flutter frame is on screen, so the
/// handoff has no blank gap between the two.
///
/// Safe to call more than once — the element is gone after the first call.
void dismissBootSplash() {
  final boot = html.document.getElementById('boot');
  if (boot == null) return;

  // Triggers the CSS opacity transition rather than snapping it away.
  boot.classes.add('boot--done');

  // The page is scroll-locked while the splash covers it; hand scrolling back
  // to the app now that it owns the viewport.
  html.document.documentElement?.style.overflow = '';
  html.document.body?.style.overflow = '';

  // Remove after the fade so it can never intercept pointer events. Slightly
  // longer than the 340ms CSS transition.
  Timer(const Duration(milliseconds: 420), boot.remove);
}
