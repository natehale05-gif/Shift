import 'package:flutter/material.dart';

/// Non-web fallback (compiled for the `flutter test` VM target): sandboxed
/// iframes only exist in the browser.
Widget buildSandboxedIframe({
  required String viewKey,
  required String htmlContent,
}) {
  return const Center(
    child: Text('Live preview is available in the browser build.'),
  );
}
