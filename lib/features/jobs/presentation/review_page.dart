import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/router/route_names.dart';
import '../../../fixtures/mock_jobs.dart';
import '../../../data/models/job.dart';
import '../../../shared/widgets/app_buttons.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_header.dart';
import '../state/jobs_controller.dart';

class ReviewPage extends StatefulWidget {
  const ReviewPage({super.key, this.job});

  final Job? job;

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  Job get _job => widget.job ?? MockJobs.all.first;

  Future<void> _onApprove() async {
    final job = _job;
    final action = await showModalBottomSheet<_InterceptAction>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.ink.withValues(alpha: 0.50),
      builder: (_) => const _InterceptModal(),
    );

    if (action == null || !mounted) return;
    if (action == _InterceptAction.autoFix) {
      await _showResolving(job);
    }
    if (!mounted) return;
    await context.read<JobsController>().approveByJobId(job.id);
    if (mounted) {
      context.go(RouteNames.submitted, extra: job);
    }
  }

  Future<void> _showResolving(Job job) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _ResolvingDialog(),
    );
    await Future.delayed(const Duration(milliseconds: 1500));
    if (mounted) Navigator.of(context, rootNavigator: true).pop();
  }

  @override
  Widget build(BuildContext context) {
    final j = _job;

    return Scaffold(
      backgroundColor: AppColors.scaffold,
      body: SafeArea(
        child: Column(
          children: [
            AppHeader.page(
              kicker: AppStrings.reviewSubtitle,
              title: AppStrings.reviewApplication,
              onBack: () => context.pop(),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppConstants.screenHorizontalPadding,
                  20,
                  AppConstants.screenHorizontalPadding,
                  32,
                ),
                children: [
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: AppColors.ink,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                j.company[0],
                                style: const TextStyle(
                                  color: AppColors.accent,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 18,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    j.company,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w900,
                                      color: AppColors.ink,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${j.title} · ${j.location}',
                                    style: const TextStyle(
                                      color: AppColors.textMuted,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.softSurface,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Row(
                            children: [
                              Icon(
                                Icons.shield_outlined,
                                size: 16,
                                color: AppColors.ink,
                              ),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Review carefully before submitting. You are always in control.',
                                  style: TextStyle(
                                    color: AppColors.ink,
                                    fontSize: 12.5,
                                    height: 1.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const _DetailCard(
                    icon: Icons.description_rounded,
                    title: 'Selected resume',
                    body: 'Job-tailored Resume v3 · ATS optimized',
                  ),
                  const SizedBox(height: 12),
                  const _DetailCard(
                    icon: Icons.edit_note_rounded,
                    title: 'Cover letter preview',
                    body:
                        "Dear hiring team, I'm excited to apply because this role matches my UX, frontend, and AI product interests...",
                  ),
                  const SizedBox(height: 12),
                  const _DetailCard(
                    icon: Icons.person_outline_rounded,
                    title: 'Autofill information',
                    body:
                        'Name, email, portfolio link, education, work authorization.',
                  ),
                  const SizedBox(height: 24),
                  AppPrimaryButton(
                    label: AppStrings.approveAndAutoApply,
                    onPressed: _onApprove,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailCard extends StatelessWidget {
  const _DetailCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppColors.softSurface,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 16, color: AppColors.ink),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            body,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 13.5,
              height: 1.55,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

enum _InterceptAction { autoFix, ignoreAndSubmit }

class _InterceptModal extends StatelessWidget {
  const _InterceptModal();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.scaffold,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.20),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.error_outline_rounded,
                  color: AppColors.warning,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Agent intercept',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: AppColors.textMuted,
                        letterSpacing: 1.2,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Hold on — requirements just changed.',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: AppColors.ink,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.20),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'NEW REQUIREMENT',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          color: AppColors.categoryInputDeep,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      '10m ago',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSoft,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Figma Prototyping',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Do you want me to rewrite your resume draft to emphasize your Figma skills before we submit?',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 13,
                    height: 1.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          )
              .animate()
              .fadeIn(duration: 220.ms)
              .moveY(begin: 6, end: 0),
          const SizedBox(height: 16),
          AppAccentButton(
            label: 'Yes, auto-fix & submit',
            icon: const Icon(Icons.auto_awesome_rounded, size: 16),
            onPressed: () => Navigator.of(context).pop(_InterceptAction.autoFix),
          ),
          const SizedBox(height: 10),
          AppSecondaryButton(
            label: 'Submit as is',
            onPressed: () =>
                Navigator.of(context).pop(_InterceptAction.ignoreAndSubmit),
          ),
        ],
      ),
    );
  }
}

class _ResolvingDialog extends StatelessWidget {
  const _ResolvingDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.accent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                color: AppColors.ink,
                strokeWidth: 2.4,
              ),
            ),
            SizedBox(width: 12),
            Text(
              'Auto-fixing & Submitting...',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: AppColors.ink,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
