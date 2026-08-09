// Custom bootstrap, so the engine's configuration is ours rather than the
// template's defaults.
//
// The token lines below are replaced at build time by `flutter build web`.
{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  config: {
    // Flutter's engine downloads a fallback font from **fonts.gstatic.com**
    // when it meets a code point none of the bundled faces covers. That is a
    // third-party request on a cold load, which means: a disclosure on both
    // stores' privacy questionnaires, a dependency on Google being reachable,
    // and nothing at all for a user who is offline.
    //
    // Pointed at our own origin instead. Today the directory is empty and the
    // app is unaffected — verified, not assumed: this build renders correctly
    // with the gstatic request blocked, because every glyph the app uses is in
    // the bundled fonts, and the engine treats a failed fallback download as a
    // non-fatal miss.
    //
    // **That stops being true in N2**, when the composer accepts arbitrary
    // text: emoji and non-Latin scripts are exactly what a fallback is for.
    // `web/fonts/fallback/README.md` says what has to land here first.
    fontFallbackBaseUrl: 'fonts/fallback/',
  },
});
