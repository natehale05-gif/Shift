/// Off-web: there is nowhere to redirect to and come back from.
///
/// Not an oversight. A desktop or mobile build has no URL of its own for the
/// provider to return to — that needs a registered deep link, which is N7's
/// signing work — so sending someone to a browser would strand them: they would
/// sign in successfully in a tab, and this app would never hear about it.
///
/// So the surfaces ask [canRedirect] and offer email instead. Saying "not here"
/// is better than a button that appears to work and does not.
const bool canRedirect = false;

/// Never called: every caller checks [canRedirect] first. Present because the
/// two arms must declare the same names, which
/// `tool/scan_conditional_imports.py` enforces.
void redirectTo(Uri url) {}

/// Nothing to clean up when nothing navigated.
void clearCallbackFragment() {}
