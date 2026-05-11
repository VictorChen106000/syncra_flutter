import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/router/route_names.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key, this.target = RouteNames.login});

  final String target;

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 2450), () {
      if (mounted) context.go(widget.target);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      body: Stack(
        alignment: Alignment.center,
        children: [
          // Ambient lime glow
          Container(
            width: 260,
            height: 260,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.accent.withValues(alpha: 0.30),
            ),
          )
              .animate()
              .scale(
                begin: const Offset(0.5, 0.5),
                end: const Offset(1.2, 1.2),
                duration: 750.ms,
                curve: Curves.easeOut,
              )
              .then(delay: 1250.ms)
              .scale(
                begin: const Offset(1.2, 1.2),
                end: const Offset(0, 0),
                duration: 450.ms,
                curve: Curves.easeIn,
              ),

          // Expanding black square morph
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: AppColors.ink,
              borderRadius: BorderRadius.circular(40),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.20),
                  blurRadius: 30,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.star_rounded,
              color: AppColors.accent,
              size: 48,
            )
                .animate(delay: 100.ms)
                .scale(
                  begin: const Offset(0, 0),
                  end: const Offset(1, 1),
                  duration: 600.ms,
                  curve: Curves.easeOutBack,
                )
                .then(delay: 1100.ms)
                .scale(
                  begin: const Offset(1, 1),
                  end: const Offset(0, 0),
                  duration: 400.ms,
                  curve: Curves.easeIn,
                ),
          )
              .animate()
              .scale(
                begin: const Offset(0, 0),
                end: const Offset(1, 1),
                duration: 600.ms,
                curve: Curves.easeOutBack,
              )
              .then(delay: 1100.ms)
              .scale(
                begin: const Offset(1, 1),
                end: const Offset(40, 40),
                duration: 600.ms,
                curve: Curves.easeInCirc,
              ),
        ],
      ),
    );
  }
}
