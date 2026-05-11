import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/router/route_names.dart';

class MorningBriefPage extends StatelessWidget {
  const MorningBriefPage({super.key, this.userName = 'Daryn'});

  final String userName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ink,
      body: Stack(
        children: [
          // Ambient blob
          Positioned(
            top: MediaQuery.sizeOf(context).height * 0.18,
            right: -100,
            child: Container(
              width: 360,
              height: 360,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.accent.withValues(alpha: 0.20),
              ),
            )
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .scale(
                  duration: 4.seconds,
                  begin: const Offset(1, 1),
                  end: const Offset(1.15, 1.15),
                  curve: Curves.easeInOut,
                )
                .fadeIn(duration: 1.seconds),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Spacer(),
                  Text(
                    '${AppStrings.goodMorning}\n$userName.',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 40,
                      fontWeight: FontWeight.w900,
                      height: 1.1,
                      letterSpacing: -1.4,
                    ),
                  ).animate().fadeIn(duration: 600.ms).moveY(begin: 14, end: 0),
                  const SizedBox(height: 40),
                  RichText(
                    text: const TextSpan(
                      style: TextStyle(
                        fontSize: 20,
                        height: 1.45,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                      children: [
                        TextSpan(
                          text: 'Binance ',
                          style: TextStyle(
                            color: AppColors.accent,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        TextSpan(text: 'just posted a new role.'),
                      ],
                    ),
                  ).animate(delay: 200.ms).fadeIn().moveY(begin: 8, end: 0),
                  const SizedBox(height: 12),
                  const Text(
                    '94%',
                    style: TextStyle(
                      color: AppColors.accent,
                      fontSize: 72,
                      fontWeight: FontWeight.w900,
                      height: 1.05,
                      letterSpacing: -3,
                    ),
                  )
                      .animate(delay: 350.ms)
                      .scale(
                        begin: const Offset(0.9, 0.9),
                        end: const Offset(1, 1),
                        curve: Curves.easeOutBack,
                        duration: 700.ms,
                      )
                      .fadeIn(),
                  const SizedBox(height: 8),
                  Container(
                    constraints: const BoxConstraints(maxWidth: 280),
                    child: Text(
                      "match with your profile. I've already drafted your application before your morning coffee.",
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.60),
                        fontSize: 17,
                        height: 1.45,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ).animate(delay: 500.ms).fadeIn(),
                  const Spacer(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _NextButton(onTap: () => context.go(RouteNames.jobs))
                          .animate(delay: 700.ms)
                          .scale(
                            begin: const Offset(0.8, 0.8),
                            end: const Offset(1, 1),
                            curve: Curves.easeOutBack,
                          )
                          .fadeIn(),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NextButton extends StatelessWidget {
  const _NextButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.accent,
      shape: const CircleBorder(),
      elevation: 6,
      shadowColor: AppColors.accent.withValues(alpha: 0.40),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const SizedBox(
          width: 64,
          height: 64,
          child: Icon(
            Icons.chevron_right_rounded,
            color: AppColors.ink,
            size: 32,
          ),
        ),
      ),
    );
  }
}
