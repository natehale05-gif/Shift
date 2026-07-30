import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';

/// The wait indicator for a turn that is *making* something.
///
/// The three dots say "thinking", which is right for an answer and wrong for a
/// build: writing a page or generating an image takes long enough that the
/// same idle dots read as a hang. A hammer that keeps tapping says work is
/// happening, and the label says what kind.
///
/// Deliberately drawn rather than animated from an asset: it is a rotation and
/// two moving dots, so a painter costs nothing to ship and scales with the
/// text around it.
class BuildingIndicator extends StatefulWidget {
  /// What is being made — "Building" for code, "Drawing" for an image.
  final String label;

  const BuildingIndicator({super.key, required this.label});

  @override
  State<BuildingIndicator> createState() => _BuildingIndicatorState();
}

class _BuildingIndicatorState extends State<BuildingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 720),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppSemanticColors>()!;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => CustomPaint(
            size: const Size(26, 22),
            painter: _HammerPainter(
              t: _controller.value,
              color: theme.colorScheme.primary,
              sparkColor: colors.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          widget.label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: colors.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// One swing per cycle: wind up slowly, strike fast, and throw two sparks on
/// contact. The asymmetry is the whole effect — a hammer that moves at a
/// constant speed reads as a wobble, not a blow.
class _HammerPainter extends CustomPainter {
  final double t;
  final Color color;
  final Color sparkColor;

  _HammerPainter({
    required this.t,
    required this.color,
    required this.sparkColor,
  });

  /// 0 at rest, 1 at the moment of impact.
  double get _swing {
    const strikeAt = 0.55;
    if (t < strikeAt) {
      // Wind up: ease out, so it slows as it reaches the top.
      final p = t / strikeAt;
      return 1 - math.pow(p, 2.4).toDouble();
    }
    // Recoil after contact.
    final p = (t - strikeAt) / (1 - strikeAt);
    return math.sin(p * math.pi) * 0.25;
  }

  /// How lit the sparks are: a brief flash right after impact.
  double get _spark {
    const strikeAt = 0.55;
    if (t < strikeAt) return 0;
    final p = (t - strikeAt) / 0.3;
    return p > 1 ? 0 : 1 - p;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final anvilY = size.height - 3;

    // The block being struck.
    final anvil = Paint()
      ..color = sparkColor.withValues(alpha: 0.35)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(2, anvilY - 3, size.width - 4, 3),
        const Radius.circular(1.5),
      ),
      anvil,
    );

    // The hammer pivots about a point above the anvil's left end.
    final pivot = Offset(size.width * 0.28, anvilY - 4);
    canvas.save();
    canvas.translate(pivot.dx, pivot.dy);
    // -70° fully raised, ~-8° at contact.
    canvas.rotate((-8 - 62 * _swing) * math.pi / 180);

    final handle = Paint()
      ..color = color.withValues(alpha: 0.85)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset.zero, const Offset(11, 0), handle);

    final head = Paint()..color = color;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(9, -4.5, 6, 9),
        const Radius.circular(1.5),
      ),
      head,
    );
    canvas.restore();

    if (_spark <= 0) return;
    final spark = Paint()..color = color.withValues(alpha: _spark);
    final reach = 3 + 3 * (1 - _spark);
    final contact = Offset(size.width * 0.66, anvilY - 5);
    canvas.drawCircle(contact.translate(-reach, -reach), 1.2, spark);
    canvas.drawCircle(contact.translate(reach * 0.8, -reach * 1.2), 1, spark);
  }

  @override
  bool shouldRepaint(_HammerPainter old) =>
      old.t != t || old.color != color || old.sparkColor != sparkColor;
}
