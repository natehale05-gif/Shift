import 'package:flutter/material.dart';

import '../../core/design/metrics.dart';
import '../../core/design/palette.dart';

/// Off-web there is no frame to render a page in.
///
/// `webview_flutter` has no Linux support and a weak Windows one, so an
/// embedded browser would make one of the desktop targets second-class — the
/// same trade v1 measured and declined. The honest answer is to say the preview
/// opens elsewhere rather than to show a rectangle that never fills in.
///
/// Which platform this build resolved to, asserted by a test because choosing
/// the wrong arm produces no error — just a preview that silently never
/// renders.
const String sandboxKind = 'unavailable';

Widget buildSandboxedPreview({
  required String viewKey,
  required String htmlContent,
}) =>
    Builder(
      builder: (context) {
        final c = context.colors;
        final text = Theme.of(context).textTheme;
        return Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.all(Space.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.open_in_new_rounded, size: 20, color: c.textFaint),
              const SizedBox(height: Space.sm),
              Text(
                'Preview opens in your browser on this platform.',
                textAlign: TextAlign.center,
                style: text.bodySmall?.copyWith(color: c.textMuted),
              ),
              const SizedBox(height: Space.xxs),
              Text(
                'The Code tab shows exactly what was written.',
                textAlign: TextAlign.center,
                style: text.bodySmall?.copyWith(color: c.textFaint),
              ),
            ],
          ),
        );
      },
    );
