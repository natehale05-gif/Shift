import 'dart:convert';

import 'package:flutter/services.dart';

/// Builds the HTML page that runs a React/JSX artifact in the artifact
/// sandbox.
///
/// A JSX artifact used to be shown as source and nothing else — the Preview tab
/// fell through to the same highlighted code as the Code tab, so the two tabs
/// showed the same thing. Running it needs three things the browser does not
/// have: React, ReactDOM, and something to turn JSX into JavaScript. All three
/// are bundled (see `assets/js/jsx/README.md`) rather than fetched from a CDN,
/// so a preview works offline and behind a filter.
class JsxPreview {
  JsxPreview._();

  static const _reactAsset = 'assets/js/jsx/react.min.js';
  static const _reactDomAsset = 'assets/js/jsx/react-dom.min.js';
  static const _transformAsset = 'assets/js/jsx/sucrase.min.js';

  static String? _react;
  static String? _reactDom;
  static String? _transform;

  /// Whether this can run the artifact — decided from [language] first, and
  /// only then from [code].
  static bool handles(String? language, [String code = '']) {
    final lang = language?.toLowerCase().trim() ?? '';
    if (const {'jsx', 'tsx', 'react', 'javascriptreact', 'typescriptreact'}
        .contains(lang)) {
      return true;
    }
    // Models label React as ```javascript at least as often as ```jsx, so a
    // plain js/ts fence is sniffed — but narrowly: it has to import React
    // *and* contain a tag, which ordinary JavaScript does not. A looser test
    // would send a `.js` file containing a `<` to a renderer that shows
    // nothing, and a blank pane is worse than a code listing.
    if (!const {'js', 'javascript', 'ts', 'typescript', 'mjs'}.contains(lang)) {
      return false;
    }
    return _importsReact.hasMatch(code) && _looksLikeJsx.hasMatch(code);
  }

  static final _importsReact =
      RegExp(r'''(import\s+[^;]*from\s+['"]react['"]|require\(['"]react['"]\))''');

  /// A tag returned or assigned — `return <div`, `=> <Foo`, `= (<div`.
  static final _looksLikeJsx =
      RegExp(r'(return\s*\(?\s*<[A-Za-z]|=>\s*\(?\s*<[A-Za-z])');

  static bool isTypeScript(String? language) {
    final lang = language?.toLowerCase().trim() ?? '';
    return const {'tsx', 'ts', 'typescript', 'typescriptreact'}.contains(lang);
  }

  /// The runnable page for [code]. Loads the bundled libraries once per
  /// session and keeps them, since a user previewing one JSX artifact usually
  /// previews another.
  static Future<String> page(String code, {bool typescript = false}) async {
    _react ??= await rootBundle.loadString(_reactAsset);
    _reactDom ??= await rootBundle.loadString(_reactDomAsset);
    _transform ??= await rootBundle.loadString(_transformAsset);
    return buildPage(
      code: code,
      typescript: typescript,
      react: _react!,
      reactDom: _reactDom!,
      transform: _transform!,
    );
  }

  /// Pure page assembly, separated from asset loading so the wiring — the
  /// require shim, how the component is found, how errors surface — is
  /// testable without a Flutter binding or 348 KB of vendored JavaScript.
  static String buildPage({
    required String code,
    required bool typescript,
    required String react,
    required String reactDom,
    required String transform,
  }) {
    // JSON-encoded rather than interpolated: the source is arbitrary text and
    // will contain quotes and backslashes. The same lesson the mermaid
    // renderer already learned.
    //
    // `jsonEncode` is not enough on its own. It does not escape `/`, so a
    // `</script>` anywhere in the component — in a string, in a comment, in
    // JSX that renders a script tag — closes this page's script block early
    // and the rest of the source spills into the document as markup. Escaping
    // the slash is invisible to JavaScript and closes that hole.
    final source = jsonEncode(code).replaceAll('</', r'<\/');
    return '''<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
  html, body { margin: 0; padding: 0; background: #fff; }
  body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto,
         Helvetica, Arial, sans-serif; }
  #shift-error { margin: 0; padding: 16px; white-space: pre-wrap;
    font: 12px/1.5 ui-monospace, SFMono-Regular, Menlo, monospace;
    color: #b00020; background: #fff5f5; }
</style>
</head>
<body>
<div id="root"></div>
<script>$react</script>
<script>$reactDom</script>
<script>$transform</script>
<script>
(function () {
  var source = $source;

  function fail(what, err) {
    var pre = document.createElement('pre');
    pre.id = 'shift-error';
    pre.textContent = what + '\\n\\n' + (err && err.stack ? err.stack : err);
    document.body.appendChild(pre);
  }

  // The transform emits CommonJS, so the page has to answer require(). Only
  // the React modules are resolvable — anything else would need a bundler, and
  // failing by name is clearer than failing with "undefined is not a function"
  // three frames deep.
  var modules = {
    'react': window.React,
    'react-dom': window.ReactDOM,
    'react-dom/client': window.ReactDOM,
  };
  function require(name) {
    if (modules[name]) return modules[name];
    throw new Error(
      'This preview can only import react and react-dom. It asked for "' +
      name + '", which would need a build step.');
  }

  var compiled;
  try {
    compiled = window.ShiftJsx.transform(source, { typescript: $typescript });
  } catch (err) {
    fail('Could not compile this component.', err);
    return;
  }

  var module = { exports: {} };
  try {
    new Function('require', 'module', 'exports', 'React', 'ReactDOM', compiled)(
      require, module, module.exports, window.React, window.ReactDOM);
  } catch (err) {
    fail('The component threw while loading.', err);
    return;
  }

  // Components are written a few ways: a default export, a named export, or a
  // bare top-level function that was never exported at all. Anything callable
  // is worth trying rather than showing a blank pane.
  var exported = module.exports || {};
  var Component = exported.default || exported.App;
  if (!Component) {
    for (var key in exported) {
      if (typeof exported[key] === 'function') { Component = exported[key]; break; }
    }
  }
  if (!Component) {
    fail('No component to render.',
      'Export a component with `export default function App() { ... }`.');
    return;
  }

  try {
    var root = window.ReactDOM.createRoot(document.getElementById('root'));
    root.render(window.React.createElement(Component));
  } catch (err) {
    fail('The component threw while rendering.', err);
  }
})();
</script>
</body>
</html>''';
  }
}
