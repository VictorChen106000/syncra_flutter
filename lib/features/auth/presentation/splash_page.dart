import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/router/route_names.dart';
import '../../../core/theme/brand_theme.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key, this.target = RouteNames.login});

  final String target;

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  // Drives a continuous, looping rotation + breathing pulse for the mark —
  // the signature Claude "thinking" motion. Paused when the user has asked
  // the OS to reduce motion.
  late final AnimationController _loop;

  @override
  void initState() {
    super.initState();
    _loop = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    );

    Future.delayed(const Duration(milliseconds: 2450), () {
      if (mounted) context.go(widget.target);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Honour the OS "reduce motion" accessibility setting: hold the mark in a
    // calm static pose instead of looping. (HIGH-severity a11y rule.)
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _loop
        ..stop()
        ..value = 0;
    } else if (!_loop.isAnimating) {
      _loop.repeat();
    }
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    Widget mark = RepaintBoundary(
      child: SizedBox(
        width: 168,
        height: 168,
        child: AnimatedBuilder(
          animation: _loop,
          builder: (context, _) {
            final t = _loop.value;
            // Slow, calm rotation across the whole loop.
            final rotation = t * 2 * math.pi;
            // ~3 gentle breaths per loop (period ~2.6s).
            final breath = math.sin(t * 2 * math.pi * 3);
            final scale = 1 + 0.045 * breath;
            final glow = 0.55 + 0.45 * (0.5 + 0.5 * breath);

            return Stack(
              alignment: Alignment.center,
              children: [
                // Soft radial glow that pulses with the breath.
                DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        brand.accent.withValues(alpha: 0.32 * glow),
                        brand.accent.withValues(alpha: 0.0),
                      ],
                      stops: const [0.0, 0.72],
                    ),
                  ),
                  child: const SizedBox(width: 168, height: 168),
                ),
                // The rotating, breathing Claude-style sunburst.
                Transform.rotate(
                  angle: rotation,
                  child: Transform.scale(
                    scale: scale,
                    child: CustomPaint(
                      size: const Size(108, 108),
                      painter: _SunburstPainter(color: brand.accent),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );

    Widget wordmark = Text(
      AppStrings.appName,
      style: TextStyle(
        color: brand.ink,
        fontSize: 22,
        fontWeight: FontWeight.w600,
        letterSpacing: 4,
      ),
    );

    // Entrance flourishes only when motion is allowed; otherwise a plain fade
    // keeps the screen accessible without jarring transforms.
    if (!reduceMotion) {
      mark = mark
          .animate()
          .fadeIn(duration: 700.ms, curve: Curves.easeOut)
          .scale(
            begin: const Offset(0.6, 0.6),
            end: const Offset(1, 1),
            duration: 800.ms,
            curve: Curves.easeOutBack,
          );
      wordmark = wordmark
          .animate(delay: 350.ms)
          .fadeIn(duration: 700.ms, curve: Curves.easeOut)
          .slideY(begin: 0.4, end: 0, curve: Curves.easeOut);
    } else {
      mark = mark.animate().fadeIn(duration: 400.ms);
      wordmark = wordmark.animate(delay: 150.ms).fadeIn(duration: 400.ms);
    }

    return Scaffold(
      backgroundColor: brand.bg,
      body: Center(
        child: Semantics(
          label: '${AppStrings.appName}, loading',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              mark,
              const SizedBox(height: 28),
              wordmark,
            ],
          ),
        ),
      ),
    );
  }
}

/// Draws the Claude/Anthropic-style radiating burst: rounded "ray" spokes of
/// gently varying length fanning out from a common center.
class _SunburstPainter extends CustomPainter {
  _SunburstPainter({required this.color});

  final Color color;

  // Relative spoke lengths (0–1) — the slight irregularity gives the mark its
  // organic, hand-drawn burst quality rather than a uniform asterisk.
  static const List<double> _lengths = [
    1.0, 0.74, 0.92, 0.68, 0.86, 0.74,
    1.0, 0.74, 0.86, 0.68, 0.92, 0.74,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxR = size.width / 2;
    final innerR = maxR * 0.16;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = maxR * 0.155;

    final count = _lengths.length;
    for (var i = 0; i < count; i++) {
      final angle = (i / count) * 2 * math.pi - math.pi / 2;
      final dir = Offset(math.cos(angle), math.sin(angle));
      final outerR = innerR + (maxR - innerR) * _lengths[i];
      canvas.drawLine(center + dir * innerR, center + dir * outerR, paint);
    }
  }

  @override
  bool shouldRepaint(_SunburstPainter oldDelegate) =>
      oldDelegate.color != color;
}
