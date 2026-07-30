import 'dart:math';

import 'package:flutter/material.dart';

/// The animals that can turn up above a new chat's greeting.
enum WalkingAnimal { deer, rabbit, fox }

/// Which animal this blank chat gets. Pure, so "you never get the same one
/// twice running" is testable without pumping a widget.
///
/// [avoid] is the one the last new chat showed. Skipping it matters more here
/// than it does for the greetings: with only three animals, plain random
/// repeats itself about a third of the time, which reads as broken rather than
/// random.
WalkingAnimal animalForSeed(int seed, {WalkingAnimal? avoid}) {
  final choices = WalkingAnimal.values.where((a) => a != avoid).toList();
  return choices[seed.abs() % choices.length];
}

/// One animal, walking back and forth on an invisible line.
///
/// Replaces the sparkle that used to sit above the greeting — a static glyph
/// that was the same on every visit, in an app whose whole empty state is about
/// not being the same on every visit.
class WalkingAnimalStrip extends StatefulWidget {
  final WalkingAnimal animal;
  final Color color;
  final double width;
  final double height;

  const WalkingAnimalStrip({
    super.key,
    required this.animal,
    required this.color,
    this.width = 200,
    this.height = 56,
  });

  @override
  State<WalkingAnimalStrip> createState() => _WalkingAnimalStripState();
}

class _WalkingAnimalStripState extends State<WalkingAnimalStrip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    // One full there-and-back. Slow enough to read as an animal rather than a
    // loading spinner — this sits above a greeting, it is not progress.
    duration: Duration(milliseconds: switch (widget.animal) {
      WalkingAnimal.deer => 11000,
      WalkingAnimal.rabbit => 8000,
      WalkingAnimal.fox => 9000,
    }),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: WalkingAnimalPainter(
            animal: widget.animal,
            color: widget.color,
            t: _controller.value,
          ),
        ),
      ),
    );
  }
}

/// Draws the animal as a flat silhouette.
///
/// Silhouettes rather than illustrations: at this size the recognisable part of
/// a deer is its antlers, of a rabbit its ears, and of a fox its tail — all
/// outline, none of it colour. It also means one accent colour works in both
/// themes without a palette per animal.
class WalkingAnimalPainter extends CustomPainter {
  final WalkingAnimal animal;
  final Color color;

  /// Position in the loop, 0–1. The first half walks right, the second walks
  /// back — so the animal turns around rather than teleporting to the start.
  final double t;

  WalkingAnimalPainter({
    required this.animal,
    required this.color,
    required this.t,
  });

  /// The drawing box every animal is composed in, facing right, feet on the
  /// bottom edge. Scaled to fit the strip's height.
  static const _boxWidth = 46.0;
  static const _boxHeight = 40.0;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.height / _boxHeight;
    final drawnWidth = _boxWidth * scale;
    // A triangle wave: out along the strip, then back.
    final outbound = t < 0.5;
    final leg = outbound ? t * 2 : (1 - t) * 2;
    final travel = (size.width - drawnWidth) * leg;

    // Gait phase advances with distance covered, not with wall time, so the
    // legs stay in step with the movement instead of drifting against it.
    final stridesPerLoop = switch (animal) {
      WalkingAnimal.deer => 14.0,
      WalkingAnimal.rabbit => 9.0,
      WalkingAnimal.fox => 15.0,
    };
    final gait = (leg * stridesPerLoop) % 1.0;

    canvas.save();
    canvas.translate(travel, 0);
    canvas.scale(scale);
    if (!outbound) {
      // Mirror in place so the animal faces the way it is going. Without the
      // matching translate it would slide half a body width on the turn.
      canvas.translate(_boxWidth, 0);
      canvas.scale(-1, 1);
    }

    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    switch (animal) {
      case WalkingAnimal.deer:
        _paintDeer(canvas, fill, stroke, gait);
      case WalkingAnimal.rabbit:
        _paintRabbit(canvas, fill, stroke, gait);
      case WalkingAnimal.fox:
        _paintFox(canvas, fill, stroke, gait);
    }
    canvas.restore();
  }

  /// One leg, hip to foot, bending at a knee. [phase] offsets it within the
  /// gait so the four legs do not move as one.
  void _leg(
    Canvas canvas,
    Paint stroke,
    double hipX,
    double hipY,
    double length,
    double phase, {
    double width = 1.6,
    double swing = 0.34,
  }) {
    final angle = phase * 2 * pi;
    final reach = sin(angle) * length * swing;
    // The foot lifts only on the forward half of the swing — a leg that rises
    // while it is behind the body reads as a limp.
    final lift = max(0.0, cos(angle)) * length * 0.16;
    final footX = hipX + reach;
    final footY = hipY + length - lift;
    final kneeX = hipX + reach * 0.45 + 0.6;
    final kneeY = hipY + length * 0.55;

    canvas.drawPath(
      Path()
        ..moveTo(hipX, hipY)
        ..lineTo(kneeX, kneeY)
        ..lineTo(footX, footY),
      stroke..strokeWidth = width,
    );
  }

  void _paintDeer(Canvas canvas, Paint fill, Paint stroke, double gait) {
    // Legs behind the body, so the body's fill hides the hips.
    _leg(canvas, stroke, 13, 22, 17, gait, width: 1.7);
    _leg(canvas, stroke, 28, 22, 17, gait + 0.5, width: 1.7);
    _leg(canvas, stroke, 16, 22, 17, gait + 0.5, width: 1.9);
    _leg(canvas, stroke, 31, 22, 17, gait, width: 1.9);

    // Body.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: const Offset(21, 18), width: 23, height: 11),
        const Radius.circular(5.5),
      ),
      fill,
    );

    // Neck: thick stroke rather than a shape, so it joins the body cleanly.
    canvas.drawLine(const Offset(30, 16), const Offset(35.5, 8),
        stroke..strokeWidth = 4.4);

    // Head, muzzle pointing forward.
    canvas.save();
    canvas.translate(36.5, 6.5);
    canvas.rotate(0.45);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: 9.5, height: 4.6),
        const Radius.circular(2.3),
      ),
      fill,
    );
    canvas.restore();

    // Ear.
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(34, 4.4), width: 3.4, height: 2.2),
      fill,
    );

    // Antlers — the whole reason a deer reads as a deer at this size.
    stroke.strokeWidth = 1.25;
    for (final lean in [0.0, 1.8]) {
      final base = Offset(34.5 + lean, 3.6);
      canvas.drawPath(
        Path()
          ..moveTo(base.dx, base.dy)
          ..lineTo(base.dx + 0.8, base.dy - 5.5)
          ..moveTo(base.dx + 0.35, base.dy - 2.4)
          ..lineTo(base.dx - 2.2, base.dy - 4.6)
          ..moveTo(base.dx + 0.7, base.dy - 4.4)
          ..lineTo(base.dx + 3.1, base.dy - 6.2),
        stroke,
      );
    }

    // Short upright tail.
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(9.2, 14.4), width: 2.6, height: 4.2),
      fill,
    );
  }

  void _paintRabbit(Canvas canvas, Paint fill, Paint stroke, double gait) {
    // A rabbit hops. Walking one on four legs like a dog would be the wrong
    // animal with the right ears.
    final airborne = gait < 0.62;
    final arc = airborne ? sin(gait / 0.62 * pi) : 0.0;
    final rise = arc * 7.0;
    // Stretched at take-off and landing, tucked at the top of the arc.
    final tuck = arc;

    canvas.save();
    canvas.translate(0, -rise);

    // Hind leg. Drawn as a line it read as dangling wire; drawn as a filled
    // outline it came out a slab. A rounded haunch plus the long flat foot —
    // the one part of a rabbit's leg anyone would draw from memory.
    // The legs rise with the body rather than staying planted — this canvas is
    // already translated up by the hop, so anchoring the foot to the ground
    // left it floating, detached, under an airborne rabbit.
    final haunchY = 30.5 - tuck * 1.5;
    canvas.save();
    canvas.translate(14.5, haunchY);
    canvas.rotate(-0.18 + tuck * 0.32);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 11.5, height: 15),
      fill,
    );
    canvas.restore();
    final footY = haunchY + 8.4;
    canvas.drawLine(
      Offset(11.0 + tuck * 3.0, footY),
      Offset(20.5, footY),
      stroke..strokeWidth = 3.2,
    );
    // Front leg: reaches forward on the way down, folds under on the way up.
    canvas.drawPath(
      Path()
        ..moveTo(27, 26)
        ..lineTo(28.8 + (1 - tuck) * 1.4, 32 - tuck * 3.2)
        ..lineTo(30.5 + (1 - tuck) * 2.4, 39.5 - tuck * 7.5),
      stroke..strokeWidth = 2.6,
    );

    // Body — rounder and lower than the others.
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(20, 25), width: 21, height: 15),
      fill,
    );

    // Head.
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(30.5, 19.5), width: 11, height: 9.5),
      fill,
    );

    // Ears, laid back a little at the top of the hop the way a real one does.
    for (final ear in [(-0.16, 29.5), (0.12, 32.0)]) {
      canvas.save();
      canvas.translate(ear.$2, 15.5);
      canvas.rotate(ear.$1 + 0.22 + tuck * 0.28);
      canvas.drawOval(
        Rect.fromCenter(center: const Offset(0, -6), width: 3.8, height: 14),
        fill,
      );
      canvas.restore();
    }

    // Scut.
    canvas.drawCircle(const Offset(9.6, 21.5), 3.1, fill);
    canvas.restore();
  }

  void _paintFox(Canvas canvas, Paint fill, Paint stroke, double gait) {
    _leg(canvas, stroke, 14, 25, 14, gait, width: 1.7, swing: 0.4);
    _leg(canvas, stroke, 26, 25, 14, gait + 0.5, width: 1.7, swing: 0.4);
    _leg(canvas, stroke, 16.5, 25, 14, gait + 0.5, width: 1.9, swing: 0.4);
    _leg(canvas, stroke, 28.5, 25, 14, gait, width: 1.9, swing: 0.4);

    // Tail: the fox's whole silhouette, so it has to read as a brush rather
    // than a spike. A thick round-capped stroke gives the bulk in one move —
    // drawn as an outline it came out a thin flick. Counter-swings the gait.
    final sway = sin(gait * 2 * pi) * 1.8;
    canvas.drawPath(
      Path()
        ..moveTo(14, 22)
        ..quadraticBezierTo(5.5, 23 + sway, 3.5, 12.5 + sway),
      stroke
        ..strokeWidth = 8.0
        ..strokeCap = StrokeCap.round,
    );

    // Body — long and low.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: const Offset(21, 21), width: 24, height: 10),
        const Radius.circular(5),
      ),
      fill,
    );

    // Head, then a shorter snout wedge on top of it. One pentagon made the
    // whole head a beak.
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(31.5, 18.5), width: 10, height: 9),
      fill,
    );
    canvas.drawPath(
      Path()
        ..moveTo(33, 15.8)
        ..lineTo(40.5, 19.8)
        ..lineTo(33, 21.8)
        ..close(),
      fill,
    );

    // Ears.
    for (final ear in [28.0, 32.0]) {
      canvas.drawPath(
        Path()
          ..moveTo(ear, 16.5)
          ..lineTo(ear + 1.3, 9.8)
          ..lineTo(ear + 3.8, 15.6)
          ..close(),
        fill,
      );
    }
  }

  @override
  bool shouldRepaint(WalkingAnimalPainter old) =>
      old.t != t || old.animal != animal || old.color != color;
}
