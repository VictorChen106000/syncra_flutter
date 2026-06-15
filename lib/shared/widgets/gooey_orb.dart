import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/brand_theme.dart';
import '../../core/utils/motion.dart';

/// A flat, single-colour lime "gooey" blob built entirely from Flutter
/// primitives — a [CustomPainter] path whose outline morphs continuously.
/// No glow, no blur, no image assets.
///
/// It's also playful: drag on it and the blob stretches toward your finger
/// like goo, then springs back with a soft elastic wobble when released.
class GooeyOrb extends StatefulWidget {
  const GooeyOrb({super.key, this.size = 132});

  /// Overall footprint. The blob sits inside with room to wobble and stretch.
  final double size;

  @override
  State<GooeyOrb> createState() => _GooeyOrbState();
}

class _GooeyOrbState extends State<GooeyOrb> with TickerProviderStateMixin {
  // A long, seamless morph loop — slow enough that it never looks repetitive.
  late final AnimationController _morph = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  );

  // Drives the elastic spring-back after the user lets go of a pull.
  late final AnimationController _spring = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  );

  /// Live pull displacement from centre while a drag is in progress.
  Offset _pull = Offset.zero;

  /// Pull captured at the moment of release — the spring eases this to zero.
  Offset _releasePull = Offset.zero;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Honour "Reduce Motion": loop only when motion is allowed.
    if (shouldAnimate(context)) {
      if (!_morph.isAnimating) _morph.repeat();
    } else {
      _morph.stop();
    }
  }

  @override
  void dispose() {
    _morph.dispose();
    _spring.dispose();
    super.dispose();
  }

  double get _maxPull => widget.size * 0.30;

  Offset _clampPull(Offset raw) {
    final d = raw.distance;
    return d <= _maxPull ? raw : raw / d * _maxPull;
  }

  Offset _pullFrom(Offset localPosition) {
    final centre = Offset(widget.size / 2, widget.size / 2);
    return _clampPull(localPosition - centre);
  }

  void _onPanStart(DragStartDetails d) {
    _spring.reset();
    setState(() => _pull = _pullFrom(d.localPosition));
  }

  void _onPanUpdate(DragUpdateDetails d) {
    setState(() => _pull = _pullFrom(d.localPosition));
  }

  void _onPanEnd(DragEndDetails d) {
    _releasePull = _pull;
    _spring.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final color = context.brand.accent;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: GestureDetector(
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: Listenable.merge([_morph, _spring]),
            builder: (context, _) {
              // Once released, ease the pull back to zero with an elastic
              // wobble; while dragging, follow the finger directly.
              final pull = _spring.value > 0
                  ? _releasePull *
                        (1 - Curves.elasticOut.transform(_spring.value))
                  : _pull;
              return CustomPaint(
                painter: _GooeyBlobPainter(
                  phase: _morph.value,
                  color: color,
                  pull: pull,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Paints a morphing lime blob: a closed path whose radius is modulated by a
/// few sine waves so the outline flows like goo. Every sine term advances by
/// an integer number of cycles per loop, so the morph repeats seamlessly.
/// A non-zero [pull] stretches the blob toward that displacement.
class _GooeyBlobPainter extends CustomPainter {
  _GooeyBlobPainter({
    required this.phase,
    required this.color,
    required this.pull,
  });

  /// 0..1 loop position.
  final double phase;
  final Color color;

  /// Displacement of the user's drag from centre, in pixels.
  final Offset pull;

  @override
  void paint(Canvas canvas, Size size) {
    // The blob leans toward the pull; its leading edge also stretches out.
    final centre = size.center(Offset.zero) + pull * 0.30;
    final baseR = size.shortestSide * 0.5 * 0.6;
    final p = phase * 2 * math.pi;
    final pullMag = pull.distance;
    final pullAngle = pullMag > 0.001 ? pull.direction : 0.0;

    final path = Path();
    const samples = 72;
    for (var i = 0; i <= samples; i++) {
      final theta = (i / samples) * 2 * math.pi;
      final wobble =
          1 +
          0.09 * math.sin(3 * theta + p) +
          0.07 * math.sin(5 * theta - 2 * p + 1.7) +
          0.05 * math.sin(2 * theta + 3 * p + 0.6);
      // Localized bulge on the edge facing the pull direction.
      final align = math.cos(theta - pullAngle);
      final lead = align > 0 ? align * align : 0.0;
      final r = baseR * wobble + pullMag * 0.5 * lead;
      final point = centre + Offset(math.cos(theta), math.sin(theta)) * r;
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();

    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_GooeyBlobPainter old) =>
      old.phase != phase || old.color != color || old.pull != pull;
}
