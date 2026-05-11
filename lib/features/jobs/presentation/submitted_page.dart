import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/router/route_names.dart';
import '../../../data/mock/mock_jobs.dart';
import '../../../data/models/job.dart';
import '../../../shared/widgets/app_buttons.dart';

class SubmittedPage extends StatelessWidget {
  const SubmittedPage({super.key, this.job});

  final Job? job;

  @override
  Widget build(BuildContext context) {
    final j = job ?? MockJobs.all.first;

    return Scaffold(
      backgroundColor: AppColors.scaffold,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.screenHorizontalPadding),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: AppColors.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 30,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Container(
                      width: 96,
                      height: 96,
                      decoration: const BoxDecoration(
                        color: AppColors.accent,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.check_rounded,
                        color: AppColors.ink,
                        size: 48,
                      ),
                    )
                        .animate()
                        .scale(
                          begin: const Offset(0.4, 0.4),
                          end: const Offset(1, 1),
                          curve: Curves.easeOutBack,
                          duration: 500.ms,
                        )
                        .fadeIn(duration: 400.ms),
                    const SizedBox(height: 20),
                    const Text(
                      AppStrings.applicationSubmitted,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: AppColors.ink,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${j.company} · ${j.title}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 13.5,
                        height: 1.55,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.softSurface,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _DetailRow(label: 'Resume', value: 'Job-tailored Resume v3'),
                          SizedBox(height: 8),
                          _DetailRow(label: 'Submitted', value: 'Just now'),
                          SizedBox(height: 8),
                          _DetailRow(label: 'Status', value: 'Awaiting reply'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    AppPrimaryButton(
                      label: AppStrings.trackApplication,
                      icon: const Icon(Icons.timeline_rounded, size: 16),
                      onPressed: () => context.go(RouteNames.tracker),
                    ),
                    const SizedBox(height: 10),
                    AppSecondaryButton(
                      label: AppStrings.backToHome,
                      onPressed: () => context.go(RouteNames.dashboard),
                    ),
                    const SizedBox(height: 6),
                    TextButton.icon(
                      onPressed: () => context.go(RouteNames.dashboard),
                      icon: const Icon(
                        Icons.undo_rounded,
                        size: 16,
                        color: AppColors.textMuted,
                      ),
                      label: const Text(
                        AppStrings.undoSubmission,
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 84,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: AppColors.textMuted,
              letterSpacing: 0.3,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
        ),
      ],
    );
  }
}
