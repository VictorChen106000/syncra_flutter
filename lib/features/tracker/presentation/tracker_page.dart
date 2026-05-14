import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/router/route_names.dart';
import '../../../data/mock/mock_tracked_applications.dart';
import '../../../data/models/job.dart';
import '../../../shared/widgets/app_header.dart';
import '../state/tracker_controller.dart';
import 'widgets/tracker_detail_sheet.dart';

class TrackerPage extends StatefulWidget {
  const TrackerPage({super.key});

  @override
  State<TrackerPage> createState() => _TrackerPageState();
}

class _TrackerPageState extends State<TrackerPage> {
  TrackerController? _bound;

  void _onMessage() {
    final msg = _bound?.consumeMessage();
    if (msg == null || !mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(msg),
        ),
      );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final c = context.read<TrackerController>();
    if (!identical(c, _bound)) {
      _bound?.removeListener(_onMessage);
      _bound = c;
      c.addListener(_onMessage);
    }
  }

  @override
  void dispose() {
    _bound?.removeListener(_onMessage);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      body: SafeArea(
        bottom: false,
        child: Consumer<TrackerController>(
          builder: (context, controller, _) {
            final apps = controller.filtered;
            final all = controller.items;
            return Column(
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
                      _SummaryStrip(apps: all),
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
                      const SizedBox(height: 12),
                      _FilterChipsRow(
                        active: controller.filter,
                        onChanged: controller.setFilter,
                      ),
                      const SizedBox(height: 16),
                      if (apps.isEmpty)
                        const _EmptyFiltered()
                      else
                        ...apps.asMap().entries.map(
                              (entry) => _TrackerCard(
                                app: entry.value,
                                onTap: () => TrackerDetailSheet.show(
                                  context,
                                  entry.value,
                                ),
                              )
                                  .animate(delay: (entry.key * 60).ms)
                                  .fadeIn()
                                  .moveY(begin: 14, end: 0),
                            ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

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

class _FilterChipsRow extends StatelessWidget {
  const _FilterChipsRow({required this.active, required this.onChanged});

  final TrackerFilter active;
  final ValueChanged<TrackerFilter> onChanged;

  static const _statuses = [
    JobStatus.submitted,
    JobStatus.viewed,
    JobStatus.replied,
    JobStatus.interview,
    JobStatus.offer,
    JobStatus.rejected,
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: _statuses.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          if (i == 0) {
            return _FilterChip(
              label: 'All',
              active: active.isAll,
              onTap: () => onChanged(const TrackerFilter.all()),
            );
          }
          final status = _statuses[i - 1];
          return _FilterChip(
            label: status.label,
            active: active.status == status,
            onTap: () => onChanged(TrackerFilter.status(status)),
          );
        },
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? AppColors.ink : AppColors.surface,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        borderRadius: BorderRadius.circular(99),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: active ? AppColors.ink : AppColors.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: active ? Colors.white : AppColors.ink,
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyFiltered extends StatelessWidget {
  const _EmptyFiltered();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: const Column(
        children: [
          Icon(Icons.inbox_outlined, size: 26, color: AppColors.textMuted),
          SizedBox(height: 10),
          Text(
            'No applications in this stage yet',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Switch filter or wait for an update.',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackerCard extends StatelessWidget {
  const _TrackerCard({required this.app, required this.onTap});

  final TrackedApplication app;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final job = app.job;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border:
                  Border.all(color: AppColors.border.withValues(alpha: 0.60)),
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
                    Expanded(
                      child: Text(
                        'Submitted ${app.submittedLabel} · Updated ${app.lastUpdate}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSoft,
                        ),
                      ),
                    ),
                    if (app.notes.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.softSurface,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.sticky_note_2_outlined,
                                size: 11, color: AppColors.ink),
                            const SizedBox(width: 4),
                            Text(
                              '${app.notes.length}',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: AppColors.ink,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
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
