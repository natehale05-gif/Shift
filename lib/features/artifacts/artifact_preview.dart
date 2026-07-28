import 'package:flutter/material.dart';

import '../../data/models/artifact.dart';
import '../../core/theme/app_spacing.dart';
import '../chat/message/markdown_message.dart';
import 'artifact_code_view.dart';
import 'iframe_view_stub.dart'
    if (dart.library.html) 'iframe_view_web.dart';

/// Renders one artifact version's "Preview" tab. HTML/SVG go through a
/// sandboxed iframe; markdown renders natively; code falls back to the
/// highlighted source view.
class ArtifactPreview extends StatelessWidget {
  final Artifact artifact;
  final int versionIndex;

  const ArtifactPreview({
    super.key,
    required this.artifact,
    required this.versionIndex,
  });

  @override
  Widget build(BuildContext context) {
    final content = artifact.versions[versionIndex].content;
    final viewKey = '${artifact.id}-v$versionIndex';

    return switch (artifact.kind) {
      ArtifactKind.html => buildSandboxedIframe(
          viewKey: viewKey,
          htmlContent: content,
        ),
      ArtifactKind.svg => buildSandboxedIframe(
          viewKey: viewKey,
          htmlContent: '<!DOCTYPE html><html><body style="margin:0;display:flex;'
              'align-items:center;justify-content:center;height:100vh;">'
              '$content</body></html>',
        ),
      ArtifactKind.markdown => SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: MarkdownMessage(text: content),
        ),
      ArtifactKind.code => ArtifactCodeView(
          code: content,
          language: artifact.language,
        ),
    };
  }
}
