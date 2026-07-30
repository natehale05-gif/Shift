import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';

/// Which tool is at work while a turn is making something.
enum BuildingTool {
  /// A hammer striking a block that keeps changing shape — building.
  hammer,

  /// A pencil sketching — drawing.
  pencil,

  /// A bow drawn across strings — anything that comes out as sound.
  violin,
}

/// The wait indicator for a turn that is *making* something.
///
/// The three dots say "thinking", which is right for an answer and wrong for a
/// build: writing a page or drawing an image takes long enough that the same
/// idle dots read as a hang. A tool that keeps moving says work is happening,
/// and the label says what kind.
///
/// Deliberately drawn rather than animated from an asset: these are a rotation
/// and a few interpolated points, so a painter costs nothing to ship and scales
/// with the text beside it.
class BuildingIndicator extends StatefulWidget {
  /// What is being made — "Building" for code, "Drawing" for an image.
  final String label;
  final BuildingTool tool;

  const BuildingIndicator({
    super.key,
    required this.label,
    this.tool = BuildingTool.hammer,
  });

  @override
  State<BuildingIndicator> createState() => _BuildingIndicatorState();
}

class _BuildingIndicatorState extends State<BuildingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    // The pencil's stroke wants longer than the hammer's blow.
    duration: Duration(
      milliseconds: widget.tool == BuildingTool.pencil ? 1500 : 720,
    ),
  )..repeat();

  /// Counts completed swings, so the struck block advances one shape per blow
  /// rather than changing mid-strike.
  int _strikes = 0;
  bool _pastStrike = false;

  @override
  void initState() {
    super.initState();
    if (widget.tool == BuildingTool.hammer) {
      _controller.addListener(_countStrikes);
    }
  }

  void _countStrikes() {
    final past = _controller.value >= _HammerPainter.strikeAt;
    if (past && !_pastStrike) setState(() => _strikes++);
    _pastStrike = past;
  }

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
        // The painter runs at 60fps for as long as the turn does. Without a
        // boundary every frame marks the whole message list dirty, so an
        // animation the size of a postage stamp repaints the transcript.
        RepaintBoundary(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => CustomPaint(
              size: const Size(30, 24),
              painter: switch (widget.tool) {
                BuildingTool.pencil => _PencilPainter(
                  t: _controller.value,
                  color: theme.colorScheme.primary,
                  lineColor: colors.textSecondary,
                ),
                BuildingTool.violin => _ViolinPainter(
                  t: _controller.value,
                  color: theme.colorScheme.primary,
                  bowColor: colors.textSecondary,
                ),
                BuildingTool.hammer => _HammerPainter(
                  t: _controller.value,
                  strikes: _strikes,
                  color: theme.colorScheme.primary,
                  sparkColor: colors.textSecondary,
                ),
              },
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

/// One swing per cycle onto a block that changes shape with every blow.
///
/// The hammer comes from the right and strikes leftward — a right-handed
/// swing, which is what reads as hammering rather than as a lever being pulled.
/// The asymmetric timing is the whole effect: wind up slowly, strike fast. A
/// hammer moving at constant speed reads as a wobble, not a blow.
class _HammerPainter extends CustomPainter {
  static const strikeAt = 0.55;

  final double t;
  final int strikes;
  final Color color;
  final Color sparkColor;

  _HammerPainter({
    required this.t,
    required this.strikes,
    required this.color,
    required this.sparkColor,
  });

  /// 1 fully raised, 0 at the moment of impact.
  double get _swing {
    if (t < strikeAt) {
      final p = t / strikeAt;
      return 1 - math.pow(p, 2.4).toDouble();
    }
    return math.sin(((t - strikeAt) / (1 - strikeAt)) * math.pi) * 0.25;
  }

  double get _spark {
    if (t < strikeAt) return 0;
    final p = (t - strikeAt) / 0.3;
    return p > 1 ? 0 : 1 - p;
  }

  /// How far the block has morphed toward its next shape. Held flat until the
  /// blow lands, then eased — the strike is what changes it.
  double get _morph {
    if (t < strikeAt) return 0;
    final p = ((t - strikeAt) / 0.35).clamp(0.0, 1.0);
    return Curves.easeOutCubic.transform(p);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final groundY = size.height - 2;
    final blockCenter = Offset(size.width * 0.3, groundY - 4.5);

    canvas.drawPath(
      _blockPath(blockCenter, 4.5, strikes + _morph),
      Paint()..color = color.withValues(alpha: 0.9),
    );

    // Pivot to the block's right, so the head comes down onto it.
    final pivot = Offset(size.width * 0.92, groundY - 6);
    canvas.save();
    canvas.translate(pivot.dx, pivot.dy);
    // Mirrored: the handle runs left from the pivot, head at the far end.
    canvas.scale(-1, 1);
    canvas.rotate((-10 - 62 * _swing) * math.pi / 180);

    canvas.drawLine(
      Offset.zero,
      const Offset(13, 0),
      Paint()
        ..color = color.withValues(alpha: 0.85)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(11, -4.5, 6, 9),
        const Radius.circular(1.5),
      ),
      Paint()..color = color,
    );
    canvas.restore();

    if (_spark <= 0) return;
    final spark = Paint()..color = color.withValues(alpha: _spark);
    final reach = 3 + 3 * (1 - _spark);
    final contact = blockCenter.translate(2, -5);
    canvas.drawCircle(contact.translate(-reach * 0.8, -reach), 1.2, spark);
    canvas.drawCircle(contact.translate(reach, -reach * 1.1), 1, spark);
  }

  /// The block, somewhere between shape `progress.floor()` and the next one.
  ///
  /// Every shape is sampled as the same number of points around its outline, so
  /// one can be tweened into the next without any special cases — a square's
  /// corners simply slide onto a triangle's, then round out into a circle.
  static Path _blockPath(Offset center, double radius, double progress) {
    const samples = 48;
    final from = progress.floor();
    final blend = progress - from;
    final a = _shapePoints(from, center, radius, samples);
    final b = _shapePoints(from + 1, center, radius, samples);

    final path = Path();
    for (var i = 0; i < samples; i++) {
      final point = Offset(
        a[i].dx + (b[i].dx - a[i].dx) * blend,
        a[i].dy + (b[i].dy - a[i].dy) * blend,
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    return path..close();
  }

  /// Square → triangle → circle → pentagon, then round again.
  static List<Offset> _shapePoints(
    int shape,
    Offset center,
    double radius,
    int samples,
  ) {
    final sides = switch (shape % 4) {
      0 => 4, // square
      1 => 3, // triangle
      2 => 0, // circle
      _ => 5, // pentagon
    };
    return [
      for (var i = 0; i < samples; i++)
        _pointAt(center, radius, i / samples, sides),
    ];
  }

  /// A point at fraction [u] around a regular polygon of [sides] (0 = circle).
  ///
  /// Polygons are walked edge by edge and interpolated *along* each edge, which
  /// is what keeps the flat sides flat while still giving evenly spaced points
  /// to tween from.
  static Offset _pointAt(Offset c, double r, double u, int sides) {
    // Odd shapes get a vertex at the top (a triangle points up); even ones are
    // rotated half a step so they rest on a flat edge. Without that, a square's
    // vertices land at top/right/bottom/left and it reads as a diamond.
    final start = sides > 0 && sides.isEven
        ? -math.pi / 2 + math.pi / sides
        : -math.pi / 2;
    if (sides == 0) {
      final angle = start + u * 2 * math.pi;
      return Offset(c.dx + r * math.cos(angle), c.dy + r * math.sin(angle));
    }
    final edge = u * sides;
    final index = edge.floor() % sides;
    final along = edge - edge.floor();
    Offset vertex(int i) {
      final angle = start + (i / sides) * 2 * math.pi;
      return Offset(c.dx + r * math.cos(angle), c.dy + r * math.sin(angle));
    }

    final from = vertex(index);
    final to = vertex((index + 1) % sides);
    return Offset(
      from.dx + (to.dx - from.dx) * along,
      from.dy + (to.dy - from.dy) * along,
    );
  }

  @override
  bool shouldRepaint(_HammerPainter old) =>
      old.t != t || old.strikes != strikes || old.color != color;
}

/// A pencil sketching a line, then lifting and starting over.
///
/// Drawing is not striking, so it gets its own motion: the tip travels along
/// the stroke it is leaving behind, tilts as a held pencil does, and the line
/// fades out at the end of the cycle rather than snapping away.
class _PencilPainter extends CustomPainter {
  final double t;
  final Color color;
  final Color lineColor;

  _PencilPainter({
    required this.t,
    required this.color,
    required this.lineColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw for the first 78% of the cycle, then lift and fade.
    const drawUntil = 0.78;
    final drawing = t < drawUntil;
    final progress = drawing ? t / drawUntil : 1.0;
    final fade = drawing ? 1.0 : 1 - ((t - drawUntil) / (1 - drawUntil));

    final left = size.width * 0.12;
    final right = size.width * 0.88;
    final baseY = size.height - 4;

    // A gentle wave, so the stroke looks drawn rather than ruled.
    double yAt(double u) => baseY - math.sin(u * math.pi) * 5;

    final stroke = Path();
    for (var i = 0; i <= 24; i++) {
      final u = (i / 24) * progress;
      final x = left + (right - left) * u;
      final y = yAt(u);
      if (i == 0) {
        stroke.moveTo(x, y);
      } else {
        stroke.lineTo(x, y);
      }
    }
    canvas.drawPath(
      stroke,
      Paint()
        ..color = lineColor.withValues(alpha: 0.55 * fade)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round,
    );

    if (!drawing) return;

    // The pencil sits at the leading end of the stroke, tilted back.
    final tip = Offset(left + (right - left) * progress, yAt(progress));
    canvas.save();
    canvas.translate(tip.dx, tip.dy);
    canvas.rotate(-55 * math.pi / 180);

    // Body, from the tip upward.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-1.7, -15, 3.4, 12),
        const Radius.circular(1),
      ),
      Paint()..color = color,
    );
    // Sharpened point.
    canvas.drawPath(
      Path()
        ..moveTo(-1.7, -3)
        ..lineTo(0, 0)
        ..lineTo(1.7, -3)
        ..close(),
      Paint()..color = color.withValues(alpha: 0.55),
    );
    // Ferrule at the top, so it reads as a pencil rather than a stick.
    canvas.drawRect(
      const Rect.fromLTWH(-1.7, -17, 3.4, 2),
      Paint()..color = color.withValues(alpha: 0.7),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PencilPainter old) =>
      old.t != t || old.color != color || old.lineColor != lineColor;
}

/// A bow drawn back and forth across a violin — anything that comes out as
/// sound.
///
/// The bow is the moving part and the instrument is still, which is the way
/// round that reads as playing. It changes direction at the ends of the stroke
/// rather than snapping back, and eases at the turn: a bow at constant speed
/// that teleports home reads as a wiper blade.
class _ViolinPainter extends CustomPainter {
  final double t;
  final Color color;
  final Color bowColor;

  _ViolinPainter({
    required this.t,
    required this.color,
    required this.bowColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.height / 24;
    canvas.save();
    canvas.scale(scale);

    final body = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final line = Paint()
      ..color = bowColor
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    // The instrument, tilted the way it sits under a chin.
    canvas.save();
    canvas.translate(13, 13);
    canvas.rotate(-0.62);

    // Body: two lobes with a waist between them, which is the whole
    // silhouette of a violin. A plain oval would be a lute.
    canvas.drawPath(
      Path()
        ..moveTo(0, -7)
        ..cubicTo(4.6, -7, 5.4, -3.4, 3.4, -1.4)
        ..cubicTo(2.2, -0.3, 2.2, 0.3, 3.4, 1.4)
        ..cubicTo(5.9, 3.7, 4.8, 8, 0, 8)
        ..cubicTo(-4.8, 8, -5.9, 3.7, -3.4, 1.4)
        ..cubicTo(-2.2, 0.3, -2.2, -0.3, -3.4, -1.4)
        ..cubicTo(-5.4, -3.4, -4.6, -7, 0, -7)
        ..close(),
      body,
    );
    // Neck and scroll.
    canvas.drawLine(
      const Offset(0, -7),
      const Offset(0, -13),
      line
        ..strokeWidth = 1.6
        ..color = color,
    );
    canvas.drawCircle(const Offset(-0.6, -13.6), 1.5, body);
    canvas.restore();

    // Bow: a triangle wave along the strings, eased at each turn so it slows
    // into the change of direction the way a real stroke does.
    final sweep = (1 - math.cos(t * 2 * math.pi)) / 2;
    final travel = -6.5 + sweep * 13;
    canvas.save();
    canvas.translate(13 + travel * 0.42, 13 - travel * 0.55);
    canvas.rotate(0.95);
    canvas.drawLine(
      const Offset(-11, 0),
      const Offset(11, 0),
      line
        ..strokeWidth = 1.5
        ..color = bowColor,
    );
    // The frog, so the bow has a direction rather than being a stick.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: const Offset(-10, 0), width: 3, height: 2.6),
        const Radius.circular(1),
      ),
      Paint()..color = bowColor,
    );
    canvas.restore();

    canvas.restore();
  }

  @override
  bool shouldRepaint(_ViolinPainter old) =>
      old.t != t || old.color != color || old.bowColor != bowColor;
}
