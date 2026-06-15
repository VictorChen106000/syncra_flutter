import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/brand_theme.dart';
import '../../core/utils/motion.dart';

/// A big circular "vessel" that fills bottom-up with animated lime water as
/// [fill] (0..1) climbs — the centrepiece of the resume-upload moment.
///
/// Two offset sine waves give the surface a living ripple, a crest highlight
/// rides the waterline, and the ring tints from neutral to accent as it fills.
/// All drawn from Flutter primitives — no shaders, no assets. Honours "Reduce
/// Motion": the ripple stops, the fill level still animates.
class WaterFillCircle extends StatefulWidget {
  const WaterFillCircle({
    super.key,
    required this.fill,
    this.size = 220,
    this.active = false,
  });

  /// Target water level, 0 (empty) → 1 (full). Implicitly animated.
  final double fill;

  /// Overall diameter.
  final double size;

  /// True while a file is actively uploading — gives the surface livelier waves.
  final bool active;

  @override
  State<WaterFillCircle> createState() => _WaterFillCircleState();
}

class _WaterFillCircleState extends State<WaterFillCircle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _wave = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (shouldAnimate(context)) {
      if (!_wave.isAnimating) _wave.repeat();
    } else {
      _wave.stop();
    }
  }

  @override
  void dispose() {
    _wave.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: widget.fill.clamp(0.0, 1.0)),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        builder: (context, level, _) {
          return RepaintBoundary(
            child: AnimatedBuilder(
              animation: _wave,
              builder: (context, _) => CustomPaint(
                size: Size.square(widget.size),
                painter: _WaterPainter(
                  level: level,
                  phase: _wave.value,
                  water: brand.accent,
                  crest: brand.accentBright,
                  ringEmpty: brand.border,
                  ringFull: brand.accent,
                  active: widget.active,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _WaterPainter extends CustomPainter {
  _WaterPainter({
    required this.level,
    required this.phase,
    required this.water,
    required this.crest,
    required this.ringEmpty,
    required this.ringFull,
    required this.active,
  });

  final double level;
  final double phase;
  final Color water;
  final Color crest;
  final Color ringEmpty;
  final Color ringFull;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final center = Offset(r, r);
    final radius = r - 2;
    final clip = Path()
      ..addOval(Rect.fromCircle(center: center, radius: radius));

    // Glow blooms as the vessel fills.
    if (level > 0.001) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = water.withValues(alpha: 0.18 * level)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
      );
    }

    canvas.save();
    canvas.clipPath(clip);

    final waterY = (1 - level) * size.height;
    final amp = level <= 0.01
        ? 0.0
        : level >= 0.99
        ? 2.5
        : (active ? 8.0 : 5.0);

    // Back wave — lighter and phase-shifted for depth.
    _wave(
      canvas,
      size,
      waterY + 3,
      amp * 0.8,
      phase + 0.5,
      size.width / 1.05,
      crest.withValues(alpha: 0.40),
    );
    // Front wave — the solid body.
    _wave(canvas, size, waterY, amp, phase, size.width / 1.45, water);

    // A bright crest line riding the surface while it's mid-fill.
    if (level > 0.02 && level < 0.99) {
      final crestPath = Path();
      const step = 6.0;
      const wavelength = 1.45;
      for (var x = 0.0; x <= size.width; x += step) {
        final y =
            waterY +
            amp *
                math.sin(
                  (x / (size.width / wavelength)) * 2 * math.pi +
                      phase * 2 * math.pi,
                );
        if (x == 0) {
          crestPath.moveTo(x, y);
        } else {
          crestPath.lineTo(x, y);
        }
      }
      canvas.drawPath(
        crestPath,
        Paint()
          ..color = crest.withValues(alpha: 0.85)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }

    canvas.restore();

    // Ring tints toward the accent as it fills.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Color.lerp(ringEmpty, ringFull, level.clamp(0.0, 1.0))!,
    );
  }

  void _wave(
    Canvas canvas,
    Size size,
    double baseY,
    double amp,
    double phase,
    double wavelength,
    Color color,
  ) {
    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(0, baseY);
    const step = 6.0;
    for (var x = 0.0; x <= size.width; x += step) {
      final y =
          baseY +
          amp * math.sin((x / wavelength) * 2 * math.pi + phase * 2 * math.pi);
      path.lineTo(x, y);
    }
    path
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_WaterPainter old) =>
      old.level != level ||
      old.phase != phase ||
      old.active != active ||
      old.water != water;
}
