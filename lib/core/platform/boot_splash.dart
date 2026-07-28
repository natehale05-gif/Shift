// Dismiss the HTML boot splash painted by web/index.html once Flutter has its
// first frame up. Resolves to the web implementation in the browser and a no-op
// stub elsewhere (tests, and any non-web target).
export 'boot_splash_stub.dart'
    if (dart.library.html) 'boot_splash_web.dart';
