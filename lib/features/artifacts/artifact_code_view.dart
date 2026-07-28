import 'package:flutter/material.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';

import '../../core/theme/app_spacing.dart';

/// The artifact panel's "Code" tab: highlighted read-only source on the
/// same fixed dark chrome as chat code blocks. Single-direction scrolling
/// with soft-wrapped lines (nested two-axis scroll views silently fail to
/// paint under CanvasKit).
class ArtifactCodeView extends StatelessWidget {
  final String code;
  final String? language;

  const ArtifactCodeView({super.key, required this.code, this.language});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF282C34),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: SizedBox(
          width: double.infinity,
          child: HighlightView(
            code,
            language: language ?? 'plaintext',
            theme: atomOneDarkTheme,
            textStyle: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ),
      ),
    );
  }
}
