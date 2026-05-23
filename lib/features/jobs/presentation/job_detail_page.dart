import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/router/route_names.dart';
import '../../../core/theme/brand_theme.dart';
import 'widgets/job_unavailable_view.dart';
import '../../../data/models/job.dart';
import '../../../shared/widgets/app_buttons.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_header.dart';

class JobDetailPage extends StatelessWidget {
  const JobDetailPage({super.key, this.job});

  final Job? job;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    if (job == null) return const JobUnavailableView();
    final j = job!;

    return Scaffold(
      backgroundColor: brand.bg,
      body: SafeArea(
        child: Column(
          children: [
            AppHeader.page(
              kicker: j.company,
              title: j.title,
              onBack: () => context.go(RouteNames.jobs),
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
                            Expanded(
                              child: Text(
                                AppStrings.matchAnalysis,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w900,
                                  color: brand.ink,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: brand.accent,
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: Text(
                                '${j.matchScore}%',
                                style: TextStyle(
                                  color: brand.onAccent,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          j.why,
                          style: TextStyle(
                            color: brand.textMuted,
                            fontSize: 13.5,
                            height: 1.55,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppStrings.requirementChecklist,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: brand.ink,
                          ),
                        ),
                        const SizedBox(height: 14),
                        ...[
                          'Resume includes relevant projects',
                          'Location and job type match',
                          'Strong design/coding keywords',
                          ...j.missingSkills.map((m) => 'Needs improvement: $m'),
                        ].map((r) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.check_circle_rounded,
                                    color: brand.accent,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      r,
                                      style: TextStyle(
                                        color: brand.ink,
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppStrings.resumeChanges,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: brand.ink,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Add role-specific keywords, strengthen project impact, and rewrite one bullet to show measurable results.',
                          style: TextStyle(
                            color: brand.textMuted,
                            fontSize: 13.5,
                            height: 1.55,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  AppPrimaryButton(
                    label: AppStrings.executeApplication,
                    onPressed: () =>
                        context.go(RouteNames.submitted, extra: j),
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
