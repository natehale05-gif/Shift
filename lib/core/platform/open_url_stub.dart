/// Inert stand-in for non-web targets (e.g. `flutter test`'s VM), so
/// pure-logic and widget code that calls [openUrl] keeps compiling under the
/// VM target which has no `dart:html`.
void openUrl(String url) {}
