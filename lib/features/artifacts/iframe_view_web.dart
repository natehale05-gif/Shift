// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

/// View types already registered with the platform-view registry. Entries
/// are permanent for the app's lifetime, so each artifact *version* gets its
/// own key — re-registering the same key would be an error, and content for
/// a key never changes.
final Set<String> _registeredViewTypes = {};

/// Renders [htmlContent] in a sandboxed iframe (`allow-scripts` only — no
/// same-origin access, so artifact code can't touch localStorage, the app,
/// or the user's session).
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
      iframe.setAttribute('sandbox', 'allow-scripts');
      iframe.srcdoc = htmlContent;
      return iframe;
    });
    _registeredViewTypes.add(viewType);
  }
  return HtmlElementView(viewType: viewType);
}
