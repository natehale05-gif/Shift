import 'package:web/web.dart' as web;

/// Fades out the HTML splash and removes it.
///
/// Called from the first post-frame callback, so the handover happens once
/// there is a real frame behind it — dismissing on `main()` entry would show
/// the user a blank page for the rest of the engine's startup, which is the
/// problem the splash exists to solve.
///
/// The node is removed rather than only hidden: it sits over the whole
/// viewport, and an invisible full-screen div swallows every pointer event
/// underneath it.
void dismissBootSplash() {
  final splash = web.document.getElementById('boot');
  if (splash == null) return;

  splash.className = 'away';
  // Matches the CSS transition. Removing immediately would cut the fade.
  // A Dart timer rather than `setTimeout`, so there is no interop shape to
  // get wrong for the sake of a delay.
  // A closure, not `splash.remove` — a tear-off of an interop extension type
  // member is rejected by the compiler, and only by the compiler: `flutter
  // analyze` accepts it happily. This is the failure mode the build gate
  // exists to catch, in miniature.
  Future<void>.delayed(const Duration(milliseconds: 300), () => splash.remove());
}
