import 'package:flutter/material.dart';

import '../core/design/metrics.dart';
import '../core/design/palette.dart';
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
              // An app-icon-shaped tile: 60pt at a ~22% corner radius, which
              // is the proportion iOS uses for a home-screen icon. Reading as
              // "an app's mark" rather than "a coloured square" is entirely a
              // function of that ratio.
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: c.accentWash,
                  borderRadius: BorderRadius.circular(13.5),
                ),
                alignment: Alignment.center,
                child: Icon(mode.activeIcon, size: 30, color: c.accent),
              ),
              const SizedBox(height: Space.lg),
              // Large Title, which is what a screen is titled with here.
              Text(mode.label, style: text.displayLarge),
              const SizedBox(height: Space.sm),
              // Body at 17, in SF — not the serif.
              //
              // The serif still exists and is still defended, but only for
              // long-form generated prose. Using it for interface copy is what
              // made this screen read as a document rather than as an app, and
              // there is no serif anywhere in Apple's own interface.
              Text(
                mode.blurb,
                style: text.bodyLarge?.copyWith(color: c.textMuted),
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

              // Which app this is, on screen.
              //
              // Two builds are published from this repo and they share a name,
              // an icon and a splash. When "am I looking at the new one?" came
              // up, nothing in either app could answer it — so the question
              // was settled by inspecting HTML, three times, while the real
              // fault was a README link. A label costs one line.
              const SizedBox(height: Space.lg),
              Text(
                'SHIFT AI v2 · rebuild in progress',
                style: text.labelSmall?.copyWith(color: c.textFaint),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
