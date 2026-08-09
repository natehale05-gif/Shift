/// Boot splash handover.
///
/// Takes down the HTML splash painted by `web/index.html`.
///
/// A no-op everywhere but the browser: only the web build has an engine that
/// takes seconds to appear, and only the web build has a document to remove
/// anything from.
///
/// Conditional on `dart.library.js_interop` rather than the older
/// `dart.library.html`, which is deprecated. The analyzer only ever resolves
/// the branch it can see, so `tool/scan_conditional_imports.py` checks that
/// both files exist and export the same names — a stale branch here passes
/// `flutter analyze` and fails only at `flutter build web`, which is exactly
/// how one shipped in v1.
library;

export 'boot_splash_stub.dart'
    if (dart.library.js_interop) 'boot_splash_web.dart';
