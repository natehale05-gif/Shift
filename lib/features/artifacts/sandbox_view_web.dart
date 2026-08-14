import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import 'preview_document.dart';

/// See the stub's copy: a test asserts this is `iframe` in a web build,
/// because picking the wrong arm raises nothing.
const String sandboxKind = 'iframe';

/// View types already registered with the platform-view registry.
///
/// Registration is permanent for the app's lifetime and re-registering a key
/// is an error, so each artifact *version* gets its own — and content for a
/// given key never changes, which is what makes that safe.
final Set<String> _registered = {};

/// What the frame is allowed to do.
///
/// **`allow-same-origin` is the one that is never here**, and that is the whole
/// security argument: without it the frame gets an opaque origin and cannot
/// reach the app's storage, its keys, or a session — whatever the generated
/// page's script tries. Granting it *alongside* `allow-scripts` would undo the
/// sandbox entirely, which is why this is a named constant with a comment
/// rather than a string somebody widens in a hurry.
///
/// The rest are there because their absence reads as the app being broken
/// rather than as a boundary, each one learned from a page that misbehaved:
/// a `<form>` made every button inside it dead; `alert()` and `confirm()` are
/// how a generated page acknowledges a click; and the popups pair lets the
/// `<base target="_blank">` the preview injects actually open, as a real page.
///
/// None of these hands the page anything belonging to the app. They let it be
/// a web page.
const _sandbox = 'allow-scripts allow-forms allow-modals allow-popups '
    'allow-popups-to-escape-sandbox';

Widget buildSandboxedPreview({
  required String viewKey,
  required String htmlContent,
}) {
  final viewType = 'shift-artifact-$viewKey';
  if (!_registered.contains(viewType)) {
    ui_web.platformViewRegistry.registerViewFactory(viewType, (int _) {
      final frame = web.document.createElement('iframe')
          as web.HTMLIFrameElement
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..setAttribute('sandbox', _sandbox)
        ..srcdoc = previewDocument(htmlContent).toJS;
      return frame;
    });
    _registered.add(viewType);
  }
  return HtmlElementView(viewType: viewType);
}
