// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

import 'preview_document.dart';

/// View types already registered with the platform-view registry. Entries
/// are permanent for the app's lifetime, so each artifact *version* gets its
/// own key — re-registering the same key would be an error, and content for
/// a key never changes.
final Set<String> _registeredViewTypes = {};

/// The sandbox an artifact runs in.
///
/// **`allow-same-origin` is the one that is never here**, and everything else
/// is a judgement about what a page needs to be usable. Without it the frame
/// gets an opaque origin: it cannot read the app's storage, its IndexedDB, or
/// the member's session, whatever the page's script tries. `allow-scripts`
/// together with `allow-same-origin` would undo the whole sandbox, which is
/// why they are not both here and why this is a constant with a comment rather
/// than a string somebody widens in a hurry.
///
/// The other four were missing, and their absence looked like the app being
/// broken rather than like a security boundary:
///
/// * `allow-forms` — a page with a `<form>` had every button inside it dead,
///   including ones handled entirely in JavaScript.
/// * `allow-modals` — `alert()` and `confirm()` are how a generated page
///   acknowledges a click. Blocked, the button did nothing at all.
/// * `allow-popups` and `allow-popups-to-escape-sandbox` — so the
///   `<base target="_blank">` the preview injects can actually open, and open
///   as a normal page rather than as another sandboxed frame.
///
/// None of these gives the page anything belonging to the app. They let it be
/// a web page.
const _sandbox = 'allow-scripts allow-forms allow-modals allow-popups '
    'allow-popups-to-escape-sandbox';

/// Renders [htmlContent] in a sandboxed iframe. See [_sandbox] for what the
/// frame is and is not allowed to do.
Widget buildSandboxedIframe({
  required String viewKey,
  required String htmlContent,
}) {
  final viewType = 'artifact-iframe-$viewKey';
  if (!_registeredViewTypes.contains(viewType)) {
    ui_web.platformViewRegistry.registerViewFactory(viewType, (int _) {
      final iframe = html.IFrameElement()
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%';
      iframe.setAttribute('sandbox', _sandbox);
      iframe.srcdoc = previewDocument(htmlContent);
      return iframe;
    });
    _registeredViewTypes.add(viewType);
  }
  return HtmlElementView(viewType: viewType);
}
