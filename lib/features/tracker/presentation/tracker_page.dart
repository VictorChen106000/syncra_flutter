import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/router/route_names.dart';
import '../../../data/mock/mock_tracked_applications.dart';
import '../../../data/models/job.dart';
import '../../../shared/widgets/app_header.dart';

class TrackerPage extends StatelessWidget {
  const TrackerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final apps = MockTrackedApplications.all;
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            AppHeader.page(
              title: AppStrings.trackerTitle,
              onBack: () => context.go(RouteNames.dashboard),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppConstants.screenHorizontalPadding,
                  16,
                  AppConstants.screenHorizontalPadding,
                  40,
                ),
                children: [
                  _SummaryStrip(apps: apps),
                  const SizedBox(height: 20),
                  Text(
                    AppStrings.trackerSubtitle,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ...apps.asMap().entries.map(
                        (entry) => _TrackerCard(app: entry.value)
                            .animate(delay: (entry.key * 60).ms)
                            .fadeIn()
                            .moveY(begin: 14, end: 0),
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

// ---------------------------------------------------------------------------
// Summary strip
// ---------------------------------------------------------------------------

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({required this.apps});

  final List<TrackedApplication> apps;

  @override
  Widget build(BuildContext context) {
    int countOf(JobStatus s) => apps.where((a) => a.status == s).length;

    final tiles = [
      (countOf(JobStatus.submitted) + countOf(JobStatus.viewed), 'In Review',
          AppColors.ink, Colors.white),
      (countOf(JobStatus.replied) + countOf(JobStatus.interview), 'Active',
          AppColors.accent, AppColors.ink),
      (countOf(JobStatus.offer), 'Offers', AppColors.categoryExploreDeep,
          Colors.white),
    ];

    return Row(
      children: [
        for (var i = 0; i < tiles.length; i++) ...[
          Expanded(
            child: _SummaryTile(
              count: tiles[i].$1,
              label: tiles[i].$2,
              bg: tiles[i].$3,
              fg: tiles[i].$4,
            ),
          ),
          if (i < tiles.length - 1) const SizedBox(width: 10),
        ],
      ],
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.count,
    required this.label,
    required this.bg,
    required this.fg,
  });

  final int count;
  final String label;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$count',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: fg,
              height: 1,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: fg.withValues(alpha: 0.80),
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tracker card
// ---------------------------------------------------------------------------

class _TrackerCard extends StatelessWidget {
  const _TrackerCard({required this.app});

  final TrackedApplication app;

  @override
  Widget build(BuildContext context) {
    final job = app.job;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.60)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
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
                  job.company[0],
                  style: const TextStyle(
                    color: AppColors.accent,
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      job.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        color: AppColors.ink,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${job.company} · ${job.location}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              _StatusBadge(status: app.status),
            ],
          ),
          const SizedBox(height: 16),
          _ProgressBar(status: app.status),
          const SizedBox(height: 14),
          if (app.nextStep != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.softSurface,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.flag_outlined,
                    size: 14,
                    color: AppColors.ink,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      app.nextStep!,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.schedule_rounded,
                  size: 12, color: AppColors.textSoft),
              const SizedBox(width: 6),
              Text(
                'Submitted ${app.submittedLabel} · Updated ${app.lastUpdate}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSoft,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final JobStatus status;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (status) {
      JobStatus.drafting => (AppColors.border, AppColors.ink),
      JobStatus.submitted => (AppColors.softSurface, AppColors.ink),
      JobStatus.viewed => (AppColors.softSurface, AppColors.ink),
      JobStatus.replied => (AppColors.accent, AppColors.ink),
      JobStatus.interview => (AppColors.ink, AppColors.accent),
      JobStatus.offer => (AppColors.categoryExploreDeep, Colors.white),
      JobStatus.rejected => (AppColors.danger, Colors.white),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        status.label.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          color: fg,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.status});

  final JobStatus status;

  @override
  Widget build(BuildContext context) {
    const stages = [
      JobStatus.submitted,
      JobStatus.viewed,
      JobStatus.replied,
      JobStatus.interview,
      JobStatus.offer,
    ];
    final isRejected = status == JobStatus.rejected;
    final currentIndex = isRejected ? -1 : stages.indexOf(status);

    return Row(
      children: List.generate(stages.length, (i) {
        final reached = !isRejected && i <= currentIndex;
        final isLast = i == stages.length - 1;
        return Expanded(
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 320),
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isRejected
                      ? AppColors.danger.withValues(alpha: 0.30)
                      : reached
                          ? AppColors.ink
                          : AppColors.border,
                ),
              ),
              if (!isLast)
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 320),
                    height: 2,
                    color: isRejected
                        ? AppColors.danger.withValues(alpha: 0.30)
                        : i < currentIndex
                            ? AppColors.ink
                            : AppColors.border,
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }
}
