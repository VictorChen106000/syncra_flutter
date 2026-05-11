import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/router/route_names.dart';
import '../../../shared/widgets/app_back_button.dart';
import '../../../shared/widgets/glass_pill.dart';

class OnboardingPage extends StatelessWidget {
  const OnboardingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
              decoration: BoxDecoration(
                color: AppColors.scaffold,
                border: Border(
                  bottom: BorderSide(
                    color: AppColors.border.withValues(alpha: 0.50),
                  ),
                ),
              ),
              child: Row(
                children: [
                  AppBackButton(onPressed: () => context.go(RouteNames.login)),
                  const Spacer(),
                  const GlassPill(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _MiniStarChip(),
                        SizedBox(width: 8),
                        Text(
                          AppStrings.onboardingHeader,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: AppColors.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 28),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                children: [
                  const _AiMessage(
                    text:
                        "Hi! I'm Syncra AI. Let's set up your career profile. Could you upload your latest resume?",
                  ).animate().fadeIn().moveY(begin: 8, end: 0),
                  const SizedBox(height: 16),
                  const _UserMessage(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.description_rounded,
                            color: AppColors.accent, size: 16),
                        SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'chris_anderson_resume.pdf',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ).animate(delay: 200.ms).fadeIn().moveY(begin: 8, end: 0),
                  const SizedBox(height: 16),
                  const _AgentTerminalBlock()
                      .animate(delay: 400.ms)
                      .fadeIn(duration: 500.ms),
                  const SizedBox(height: 16),
                  const _AiMessage(
                    text:
                        'I successfully extracted your skills! To calibrate my matching engine, what specific role are you aiming for?',
                  ).animate(delay: 700.ms).fadeIn().moveY(begin: 8, end: 0),
                  const SizedBox(height: 16),
                  const _UserMessage(
                    child: Text(
                      'UX Designer or Frontend Developer',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ).animate(delay: 850.ms).fadeIn().moveY(begin: 8, end: 0),
                  const SizedBox(height: 16),
                  const _AiMessage(
                    text:
                        "Got it! Your AI profile is ready. I'll start finding matches in the background.",
                  ).animate(delay: 1000.ms).fadeIn().moveY(begin: 8, end: 0),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => context.go(RouteNames.dashboard),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.ink,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(56),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        AppStrings.goToDashboard,
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                      ),
                      SizedBox(width: 8),
                      Icon(Icons.arrow_forward_rounded, size: 16),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniStarChip extends StatelessWidget {
  const _MiniStarChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 16,
      height: 16,
      decoration: const BoxDecoration(
        color: AppColors.ink,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: const Icon(Icons.star_rounded, color: AppColors.accent, size: 10),
    );
  }
}

class _AiMessage extends StatelessWidget {
  const _AiMessage({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: const BoxDecoration(
            color: AppColors.ink,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.star_rounded, color: AppColors.accent, size: 14),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.72,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(22),
                topRight: Radius.circular(22),
                bottomLeft: Radius.circular(4),
                bottomRight: Radius.circular(22),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 14.5,
                height: 1.55,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _UserMessage extends StatelessWidget {
  const _UserMessage({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Flexible(
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.72,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: AppColors.ink,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(22),
                topRight: Radius.circular(22),
                bottomLeft: Radius.circular(22),
                bottomRight: Radius.circular(4),
              ),
            ),
            child: child,
          ),
        ),
      ],
    );
  }
}

class _AgentTerminalBlock extends StatelessWidget {
  const _AgentTerminalBlock();

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.20),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 1,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  AppColors.accent,
                  Colors.transparent,
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _TerminalDot(color: AppColors.danger),
                    const SizedBox(width: 6),
                    _TerminalDot(color: AppColors.warning),
                    const SizedBox(width: 6),
                    _TerminalDot(color: AppColors.success),
                    const SizedBox(width: 10),
                    Text(
                      'AGENT THOUGHT PROCESS',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.50),
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.4,
                      ),
                    ),
                  ],
                ),
                const Divider(height: 22, color: Colors.white12),
                _TerminalLine(
                  prefix: '⚙',
                  text: 'Tool Call: ParseDocument(file)',
                  color: Colors.white.withValues(alpha: 0.80),
                ),
                const SizedBox(height: 4),
                const _TerminalLine(
                  prefix: '↳',
                  text: 'Extracted 420 words.',
                  color: AppColors.accent,
                  bold: true,
                  indent: 14,
                ),
                const SizedBox(height: 12),
                _TerminalLine(
                  prefix: '⚙',
                  text: 'Tool Call: ExtractSkills()',
                  color: Colors.white.withValues(alpha: 0.80),
                ),
                const SizedBox(height: 4),
                const _TerminalLine(
                  prefix: '↳',
                  text: 'Found: React, JavaScript, Figma.',
                  color: AppColors.accent,
                  bold: true,
                  indent: 14,
                ),
                const SizedBox(height: 12),
                const _TerminalLine(
                  prefix: '🔍',
                  text:
                      'Agent Decision: Missing Target Role. Asking user for input.',
                  color: AppColors.warning,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TerminalDot extends StatelessWidget {
  const _TerminalDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _TerminalLine extends StatelessWidget {
  const _TerminalLine({
    required this.prefix,
    required this.text,
    required this.color,
    this.bold = false,
    this.indent = 0,
  });

  final String prefix;
  final String text;
  final Color color;
  final bool bold;
  final double indent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: indent),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(prefix, style: TextStyle(color: color, fontSize: 11)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color,
                fontSize: 11,
                height: 1.45,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
