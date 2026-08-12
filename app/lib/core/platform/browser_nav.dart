/// Sending the page somewhere, and cleaning up after it comes back.
///
/// A sign-in redirect is the one thing in this app that navigates the whole
/// page away and returns with something in the URL. Both halves of that are
/// browser behaviour with no meaning off-web, so both live behind this pair.
///
/// **Off-web is not a stub that quietly does nothing.** There is no deep link
/// registered for the desktop and mobile builds yet, so a redirect would open a
/// browser that could never hand the session back — the app would sit on the
/// sign-in screen while a tab elsewhere showed a successful login. Better to
/// say the button is not available there, which is what [canRedirect] is for.
///
/// **The conditional key is `dart.library.js_interop`, not `dart.library.html`.**
/// The latter is false under dart2wasm, which is what this app builds with, so
/// a pair keyed on it silently takes the wrong arm on the web with no error.
library;

export 'browser_nav_io.dart'
    if (dart.library.js_interop) 'browser_nav_web.dart';
