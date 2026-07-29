import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/platform/open_url.dart';

/// Off-web preview: render it in the user's own browser.
///
/// There is no embedded engine to fall back on — `webview_flutter` has no
/// Linux support and its Windows story is thin — so rather than ship a dead
/// panel (which is what the old stub did: a line of text saying previews only
/// work in the browser build), the artifact is written to a temp file and
/// handed to the system browser. The Code tab beside this one already shows
/// the source, so nothing is hidden.
Widget buildSandboxedIframe({
  required String viewKey,
  required String htmlContent,
}) {
  return _ExternalPreview(viewKey: viewKey, htmlContent: htmlContent);
}

class _ExternalPreview extends StatefulWidget {
  final String viewKey;
  final String htmlContent;

  const _ExternalPreview({required this.viewKey, required this.htmlContent});

  @override
  State<_ExternalPreview> createState() => _ExternalPreviewState();
}

class _ExternalPreviewState extends State<_ExternalPreview> {
  String? _error;

  Future<void> _open() async {
    try {
      final dir = await getTemporaryDirectory();
      final safeKey = widget.viewKey.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      final file = File('${dir.path}/shift_preview_$safeKey.html');
      await file.writeAsBytes(utf8.encode(widget.htmlContent), flush: true);
      openUrl(file.uri.toString());
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.open_in_browser_rounded,
                size: 32, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text(
              'Preview opens in your browser',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'The desktop app has no embedded browser, so previews open in '
              'your default one. The Code tab shows the source here.',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _open,
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              label: const Text('Open preview'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text("Couldn't open the preview: $_error",
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error),
                  textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }
}
