import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/router/route_names.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  void _continue(BuildContext context) {
    context.go(RouteNames.onboarding);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ink,
      body: Stack(
        children: [
          const _LoginBackground(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Spacer(),
                  // Hero text
                  RichText(
                    text: const TextSpan(
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 44,
                        fontWeight: FontWeight.w900,
                        height: 1.05,
                        letterSpacing: -1.4,
                      ),
                      children: [
                        TextSpan(text: 'Let '),
                        TextSpan(
                          text: 'AI Agent',
                          style: TextStyle(color: AppColors.accent),
                        ),
                        TextSpan(text: '\nApply\nFor You.'),
                      ],
                    ),
                  ).animate().fadeIn(duration: 500.ms).moveY(begin: 12, end: 0, duration: 500.ms),
                  const SizedBox(height: 32),
                  _GoogleLoginButton(onTap: () => _continue(context))
                      .animate(delay: 150.ms)
                      .fadeIn(duration: 400.ms)
                      .moveY(begin: 14, end: 0),
                  const SizedBox(height: 12),
                  _AppleLoginButton(onTap: () => _continue(context))
                      .animate(delay: 250.ms)
                      .fadeIn(duration: 400.ms)
                      .moveY(begin: 14, end: 0),
                  const SizedBox(height: 12),
                  Center(
                    child: TextButton(
                      onPressed: () => _continue(context),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      ),
                      child: Text(
                        AppStrings.continueAsGuest,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.70),
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ).animate(delay: 350.ms).fadeIn(duration: 400.ms),
                  const SizedBox(height: 8),
                  Text(
                    AppStrings.loginTerms,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.40),
                      fontSize: 11,
                      height: 1.55,
                      fontWeight: FontWeight.w500,
                    ),
                  ).animate(delay: 450.ms).fadeIn(duration: 400.ms),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginBackground extends StatelessWidget {
  const _LoginBackground();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.loginGradientTop,
              AppColors.loginGradientMid,
              AppColors.ink,
            ],
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                AppColors.ink.withValues(alpha: 0.55),
                AppColors.ink,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GoogleLoginButton extends StatelessWidget {
  const _GoogleLoginButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          height: 56,
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const _GoogleLogo(size: 20),
              const SizedBox(width: 12),
              Text(
                AppStrings.continueWithGoogle,
                style: const TextStyle(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppleLoginButton extends StatelessWidget {
  const _AppleLoginButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.apple_rounded, color: Colors.white, size: 22),
              SizedBox(width: 12),
              Text(
                AppStrings.continueWithApple,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Multi-colored Google "G" rendered with overlapping shapes.
class _GoogleLogo extends StatelessWidget {
  const _GoogleLogo({this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _GoogleLogoPainter(),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  static const _blue = Color(0xFF4285F4);
  static const _green = Color(0xFF34A853);
  static const _yellow = Color(0xFFFBBC05);
  static const _red = Color(0xFFEA4335);

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final center = Offset(r, r);
    final paint = Paint()..style = PaintingStyle.fill;

    // Simplified Google "G": four quadrant arcs in brand colors.
    // We draw a circle in 4 quadrants then punch out the center.
    final rect = Rect.fromCircle(center: center, radius: r);

    void drawArc(double start, double sweep, Color color) {
      paint.color = color;
      canvas.drawArc(rect, start, sweep, true, paint);
    }

    drawArc(-1.5708, 1.5708, _blue); // top right
    drawArc(0, 1.5708, _green); // bottom right
    drawArc(1.5708, 1.5708, _yellow); // bottom left
    drawArc(3.1416, 1.5708, _red); // top left

    // Inner white circle
    paint.color = Colors.white;
    canvas.drawCircle(center, r * 0.42, paint);

    // Horizontal "G" bar
    paint.color = _blue;
    canvas.drawRect(
      Rect.fromLTWH(r, r - r * 0.10, r, r * 0.20),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
