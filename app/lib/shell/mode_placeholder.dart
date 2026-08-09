import 'package:flutter/material.dart';

import '../core/design/metrics.dart';
import '../core/design/palette.dart';
import '../core/design/typography.dart';
import 'mode.dart';

/// What a mode shows before it is built.
///
/// It says the mode is not built yet, in those words. The alternative — a
/// convincing-looking surface with dead controls — is the thing this whole
/// rebuild exists to stop doing: v1 shipped simulated websites and procedural
/// gradients that read as the product being broken rather than as a boundary,
/// and every one of those was found by a person on a phone rather than by a
/// test.
///
/// Each of these is replaced wholesale by its wave. None of them is a shell to
/// fill in.
class ModePlaceholder extends StatelessWidget {
  final AppMode mode;

  /// Which wave builds this, so the empty state answers "when", not just
  /// "not yet".
  final String wave;

  const ModePlaceholder({super.key, required this.mode, required this.wave});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(Space.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: c.accentWash,
                  borderRadius: BorderRadius.circular(Radii.md),
                ),
                alignment: Alignment.center,
                child: Icon(mode.activeIcon, size: 26, color: c.accent),
              ),
              const SizedBox(height: Space.lg),
              Text(mode.label, style: text.displayMedium),
              const SizedBox(height: Space.sm),
              Text(
                mode.blurb,
                style: ShiftType.proseStyle(c.textMuted),
              ),
              const SizedBox(height: Space.xl),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.md,
                  vertical: Space.sm,
                ),
                decoration: BoxDecoration(
                  color: c.surfaceSunken,
                  borderRadius: BorderRadius.circular(Radii.sm),
                  border: Border.all(color: c.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.construction_rounded,
                        size: 15, color: c.textFaint),
                    const SizedBox(width: Space.sm),
                    Flexible(
                      child: Text(
                        'Not built yet — lands in $wave.',
                        style: text.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
