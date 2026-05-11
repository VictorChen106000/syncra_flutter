import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/router/route_names.dart';
import '../../../data/mock/mock_jobs.dart';
import '../../../data/models/job.dart';
import '../../../shared/widgets/app_buttons.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_header.dart';
import '../../../shared/widgets/step_pill.dart';

class TailorPage extends StatelessWidget {
  const TailorPage({super.key, this.job});

  final Job? job;

  @override
  Widget build(BuildContext context) {
    final j = job ?? MockJobs.all.first;

    return Scaffold(
      backgroundColor: AppColors.scaffold,
      body: SafeArea(
        child: Column(
          children: [
            AppHeader.page(
              kicker: '${j.company} · ${j.title}',
              title: AppStrings.tailorResume,
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
                  const AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppStrings.before,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: AppColors.ink,
                          ),
                        ),
                        SizedBox(height: 10),
                        Text(
                          'Created a student app project using React and Figma.',
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 13.5,
                            height: 1.55,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  AppCard(
                    backgroundColor: AppColors.softSurface,
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppStrings.after,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: AppColors.ink,
                          ),
                        ),
                        SizedBox(height: 10),
                        Text(
                          'Designed and built a responsive AI career prototype with React, Figma workflows, and user-centered job matching features.',
                          style: TextStyle(
                            color: AppColors.ink,
                            fontSize: 13.5,
                            height: 1.55,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppStrings.keywordsAdded,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: AppColors.ink,
                          ),
                        ),
                        SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            StepPill(label: 'Responsive design'),
                            StepPill(label: 'AI workflow'),
                            StepPill(label: 'Job matching'),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  AppPrimaryButton(
                    label: AppStrings.acceptChanges,
                    onPressed: () =>
                        context.go(RouteNames.review, extra: j),
                  ),
                  const SizedBox(height: 12),
                  AppSecondaryButton(
                    label: AppStrings.editChanges,
                    onPressed: () {},
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton.icon(
                      onPressed: () => context.go(RouteNames.review, extra: j),
                      icon: const Icon(
                        Icons.undo_rounded,
                        size: 16,
                        color: AppColors.danger,
                      ),
                      label: const Text(
                        AppStrings.revertToOriginal,
                        style: TextStyle(
                          color: AppColors.danger,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
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
