import 'package:web/web.dart' as web;

/// On the web the page can navigate away and be returned to, which is the
/// whole mechanism a hosted sign-in uses.
const bool canRedirect = true;

/// Leaves for [url]. The page is replaced; nothing after this runs.
///
/// `assign` rather than `replace`, so Back still returns to the app rather than
/// to whatever was open before it. Someone who reaches a provider's sign-in
/// page and changes their mind should land where they started.
void redirectTo(Uri url) => web.window.location.assign(url.toString());

/// Removes the tokens from the address bar once they have been read.
///
/// **This is not tidiness.** The session arrives in the fragment, and a
/// fragment stays in the address bar, in browser history, and in every
/// screenshot taken of either. `replaceState` rewrites the entry in place, so
/// there is no extra history step and no reload.
void clearCallbackFragment() {
  final url = web.window.location.href;
  final hash = url.indexOf('#');
  if (hash < 0) return;
  web.window.history.replaceState(null, '', url.substring(0, hash));
}
