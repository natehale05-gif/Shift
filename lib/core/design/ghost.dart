import 'package:flutter/material.dart';

/// The ghost, drawn rather than looked up.
///
/// Material ships no ghost glyph and this app carries no icon font — adding
/// one for a single mark would be a poor trade against a 2.58 MB payload — so
/// it is a path: a rounded dome, a scalloped hem of three lobes, two eyes.
///
/// **[filled] is the on state and outline is the off state, and that is form
/// rather than colour on purpose.** A toggle whose only difference is a hue
/// is a toggle half of a room cannot read, and it has to survive a light
/// ground, a dark one and Code mode's near-black. Shape survives all three.
///
/// Lives in `core/design/` rather than in the chat feature because it is a
/// glyph, not a control: whatever else grows a private session will want the
/// same mark, and a second hand-drawn ghost would not match this one.
class GhostIcon extends StatelessWidget {
  /// Matches every other icon in the top bar. The geometry is normalised, so
  /// this is the only size knob.
  final double size;

  final Color color;

  /// Solid body with the eyes knocked out, versus a stroked outline.
  final bool filled;

  const GhostIcon({
    super.key,
    this.size = 20,
    required this.color,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        // No semantics here: the mark is never on its own. Whatever holds it
        // carries the label, and a second announcement would be read twice.
        child: CustomPaint(
          painter: _GhostPainter(color: color, filled: filled),
        ),
      );
}

class _GhostPainter extends CustomPainter {
  final Color color;
  final bool filled;

  const _GhostPainter({required this.color, required this.filled});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Everything below is a fraction of the box, so the mark is identical at
    // 16pt and at 64pt. Inset enough that a stroke does not clip at the edge.
    final left = w * 0.17;
    final right = w * 0.83;

    // Where the dome stops and the straight sides begin. Above this the shape
    // is a half-circle; below it, two verticals down to the hem.
    final waist = h * 0.45;
    final hem = h * 0.74;
    final dip = h * 0.98;

    final body = Path()
      ..moveTo(left, waist)
      // Over the top: 9 o'clock to 3 o'clock, which is clockwise on a canvas
      // whose y grows downward.
      ..arcToPoint(
        Offset(right, waist),
        radius: Radius.circular((right - left) / 2),
        clockwise: true,
      )
      ..lineTo(right, hem);

    // Three lobes, right to left. Each is one quadratic bulging past the hem,
    // so the joins between them come to a point — which is what reads as cloth
    // rather than as a row of bumps.
    const lobes = 3;
    final step = (right - left) / lobes;
    for (var i = 1; i <= lobes; i++) {
      final to = right - step * i;
      body.quadraticBezierTo(to + step / 2, dip, to, hem);
    }
    body.close();

    final eyes = Path()
      ..addOval(Rect.fromCircle(
        center: Offset(w * 0.385, h * 0.43),
        radius: w * 0.075,
      ))
      ..addOval(Rect.fromCircle(
        center: Offset(w * 0.615, h * 0.43),
        radius: w * 0.075,
      ));

    if (filled) {
      // Knocked out rather than painted in the ground colour: the button sits
      // on paper in one theme and on charcoal in another, and a hardcoded
      // "background" would be wrong in one of them.
      canvas.drawPath(
        Path.combine(PathOperation.difference, body, eyes),
        Paint()
          ..color = color
          ..style = PaintingStyle.fill
          ..isAntiAlias = true,
      );
      return;
    }

    canvas.drawPath(
      body,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.09
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true,
    );
    // Solid even in the outline state. Two rings at this size read as noise,
    // and a ghost without eyes reads as a bag.
    canvas.drawPath(eyes, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_GhostPainter old) =>
      old.color != color || old.filled != filled;
}
