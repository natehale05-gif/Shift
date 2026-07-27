import 'package:flutter/material.dart';

import '../../services/js_sandbox_service.dart';
import '../../core/theme/app_spacing.dart';

/// Console drawer under an artifact preview, showing output captured from a
/// sandboxed JavaScript run.
class ConsoleOutputView extends StatelessWidget {
  final List<ConsoleLine> lines;

  const ConsoleOutputView({super.key, required this.lines});

  static const _levelColors = {
    'error': Color(0xFFE06C75),
    'warn': Color(0xFFE5C07B),
    'info': Color(0xFF61AFEF),
    'system': Color(0xFF9DA5B4),
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 180),
      color: const Color(0xFF21252B),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (lines.isEmpty)
              const Text(
                'No output.',
                style: TextStyle(
                  color: Color(0xFF9DA5B4),
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              )
            else
              for (final line in lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    line.text,
                    style: TextStyle(
                      color: _levelColors[line.level] ??
                          const Color(0xFFABB2BF),
                      fontFamily: 'monospace',
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
