import 'package:flutter/material.dart';

import '../../core/design/metrics.dart';
import '../../core/design/palette.dart';
import '../../core/design/typography.dart';

/// The source, as written.
///
/// Selectable and scrollable in both directions: code has long lines, and
/// wrapping them silently changes what the reader thinks the file says.
/// No syntax highlighting yet — a highlighter is a dependency and a decision,
/// and an honest monospace view of the real bytes beats a coloured
/// approximation of them.
class ArtifactCodeView extends StatelessWidget {
  final String code;
  final String? language;

  const ArtifactCodeView({super.key, required this.code, this.language});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Container(
      color: c.surfaceSunken,
      child: SingleChildScrollView(
        primary: false,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Padding(
            padding: const EdgeInsets.all(Space.md),
            child: SelectableText(
              code,
              style: ShiftType.codeStyle(c.text),
            ),
          ),
        ),
      ),
    );
  }
}
