import 'dart:ui';

import 'package:flutter/material.dart';

/// Apple's "Liquid Glass" material — a blurred, translucent surface with a
/// soft specular sheen along the top edge and a hairline border that catches
/// light, the way glass panes in iOS/macOS/visionOS chrome behave. Used for
/// this app's navigation and floating controls (app bar, sidebar, composer,
/// popovers) — not for content surfaces, which stay opaque and legible.
class LiquidGlass extends StatelessWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry? padding;
  final double blurSigma;
  final double tintOpacity;
  final Border? border;
  final List<BoxShadow>? boxShadow;

  const LiquidGlass({
    super.key,
    required this.child,
    this.borderRadius = BorderRadius.zero,
    this.padding,
    this.blurSigma = 36,
    this.tintOpacity = 0.6,
    this.border,
    this.boxShadow,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final surface = theme.colorScheme.surface;

    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                surface.withValues(
                  alpha: (tintOpacity + (dark ? 0.14 : 0.08)).clamp(0, 1),
                ),
                surface.withValues(alpha: tintOpacity),
              ],
            ),
            border:
                border ??
                Border.all(
                  color: dark
                      ? Colors.white.withValues(alpha: 0.10)
                      : Colors.white.withValues(alpha: 0.65),
                  width: 1,
                ),
            boxShadow: boxShadow,
          ),
          child: Stack(
            children: [
              // A soft highlight arcing across the top — light catching the
              // curved top edge of a glass pane.
              Positioned(
                top: -60,
                left: -30,
                right: -30,
                child: IgnorePointer(
                  child: Container(
                    height: 90,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withValues(alpha: dark ? 0.05 : 0.32),
                          Colors.white.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              child,
            ],
          ),
        ),
      ),
    );
  }
}
