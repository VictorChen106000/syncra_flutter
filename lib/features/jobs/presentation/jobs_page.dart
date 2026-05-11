import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/router/route_names.dart';
import '../../../data/mock/mock_jobs.dart';
import '../../../data/models/job.dart';
import '../../../shared/widgets/app_bottom_nav.dart';
import '../../../shared/widgets/app_header.dart';
import '../../../shared/widgets/app_screen.dart';

class JobsPage extends StatefulWidget {
  const JobsPage({super.key});

  @override
  State<JobsPage> createState() => _JobsPageState();
}

class _JobsPageState extends State<JobsPage> {
  int _tabIndex = 0;
  String _query = '';
  _Filter _filter = _Filter.all;

  List<Job> get _filteredQueue {
    final all = [...MockJobs.ready, ...MockJobs.inputNeeded, ...MockJobs.exploration];
    return all.where((j) {
      final matchesFilter = switch (_filter) {
        _Filter.all => true,
        _Filter.ready => j.category == JobCategory.ready,
        _Filter.input => j.category == JobCategory.inputNeeded,
        _Filter.strategic => j.category == JobCategory.exploration,
      };
      if (!matchesFilter) return false;
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return j.title.toLowerCase().contains(q) ||
          j.company.toLowerCase().contains(q) ||
          j.location.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return AppScreen(
      showBottomNav: true,
      activeTab: BottomNavTab.agent,
      extendBehindBottomNav: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppHeader.tab(
            title: AppStrings.agentPipeline,
            subtitle: _tabIndex == 0
                ? AppStrings.agentPipelineQueueSubtitle
                : AppStrings.agentPipelineHistorySubtitle,
            bottom: _TabSwitcher(
              selectedIndex: _tabIndex,
              labels: const [AppStrings.reviewQueue, AppStrings.history],
              onChanged: (i) => setState(() => _tabIndex = i),
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: _tabIndex == 0
                  ? _ReviewQueueTab(
                      key: const ValueKey('queue'),
                      query: _query,
                      filter: _filter,
                      jobs: _filteredQueue,
                      onQueryChanged: (q) => setState(() => _query = q),
                      onFilterChanged: (f) => setState(() => _filter = f),
                    )
                  : const _HistoryTab(key: ValueKey('history')),
            ),
          ),
        ],
      ),
    );
  }
}

enum _Filter { all, ready, input, strategic }

// ---------------------------------------------------------------------------
// Tab switcher
// ---------------------------------------------------------------------------

class _TabSwitcher extends StatelessWidget {
  const _TabSwitcher({
    required this.selectedIndex,
    required this.labels,
    required this.onChanged,
  });

  final int selectedIndex;
  final List<String> labels;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.border.withValues(alpha: 0.40),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: List.generate(labels.length, (i) {
          final active = selectedIndex == i;
          return Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                color: active ? AppColors.surface : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: () => onChanged(i),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      labels[i],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: active ? AppColors.ink : AppColors.textMuted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Review Queue tab
// ---------------------------------------------------------------------------

class _ReviewQueueTab extends StatelessWidget {
  const _ReviewQueueTab({
    super.key,
    required this.query,
    required this.filter,
    required this.jobs,
    required this.onQueryChanged,
    required this.onFilterChanged,
  });

  final String query;
  final _Filter filter;
  final List<Job> jobs;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<_Filter> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.screenHorizontalPadding,
        16,
        AppConstants.screenHorizontalPadding,
        140,
      ),
      children: [
        _SearchBar(value: query, onChanged: onQueryChanged),
        const SizedBox(height: 12),
        _FilterRow(active: filter, onChanged: onFilterChanged),
        const SizedBox(height: 18),
        if (jobs.isEmpty)
          const _EmptyResults()
        else
          ...jobs.asMap().entries.map((entry) {
            return _JobCard(job: entry.value)
                .animate(delay: (entry.key * 60).ms)
                .fadeIn()
                .moveY(begin: 16, end: 0);
          }),
      ],
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.search_rounded, size: 18, color: AppColors.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              onChanged: onChanged,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
              decoration: const InputDecoration(
                hintText: AppStrings.searchJobsHint,
                hintStyle: TextStyle(
                  color: AppColors.textSoft,
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
                contentPadding: EdgeInsets.symmetric(vertical: 14),
                border: InputBorder.none,
                isCollapsed: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({required this.active, required this.onChanged});

  final _Filter active;
  final ValueChanged<_Filter> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        children: [
          for (final entry in const [
            (_Filter.all, 'All'),
            (_Filter.ready, 'Ready'),
            (_Filter.input, 'Needs Input'),
            (_Filter.strategic, 'Strategic'),
          ])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _FilterChip(
                label: entry.$2,
                active: active == entry.$1,
                onTap: () => onChanged(entry.$1),
              ),
            ),
        ],
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
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
              fontWeight: FontWeight.w800,
              color: active ? Colors.white : AppColors.ink,
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyResults extends StatelessWidget {
  const _EmptyResults();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      child: const Column(
        children: [
          Icon(Icons.search_off_rounded, size: 28, color: AppColors.textMuted),
          SizedBox(height: 10),
          Text(
            'Nothing matched',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 15,
              color: AppColors.ink,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Try a different search or clear the filter.',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Job card
// ---------------------------------------------------------------------------

class _JobCard extends StatelessWidget {
  const _JobCard({required this.job});

  final Job job;

  Color get _accentColor => switch (job.category) {
        JobCategory.ready => AppColors.ink,
        JobCategory.inputNeeded => AppColors.categoryInputDeep,
        JobCategory.exploration => AppColors.categoryExploreDeep,
      };

  IconData get _justificationIcon => switch (job.category) {
        JobCategory.ready => Icons.auto_awesome_rounded,
        JobCategory.inputNeeded => Icons.error_outline_rounded,
        JobCategory.exploration => Icons.star_rounded,
      };

  String get _primaryLabel => switch (job.category) {
        JobCategory.ready => 'Export Application',
        JobCategory.inputNeeded => 'Reply in Chat',
        JobCategory.exploration => 'Generate Draft',
      };

  IconData? get _primaryIcon => switch (job.category) {
        JobCategory.ready => null,
        JobCategory.inputNeeded => Icons.send_rounded,
        JobCategory.exploration => Icons.star_rounded,
      };

  String get _secondaryLabel => switch (job.category) {
        JobCategory.ready => '',
        JobCategory.inputNeeded => 'Skip',
        JobCategory.exploration => 'Ignore',
      };

  VoidCallback _onPrimaryTap(BuildContext context) => switch (job.category) {
        JobCategory.ready =>
          () => context.go(RouteNames.review, extra: job),
        JobCategory.inputNeeded =>
          () => context.go(RouteNames.agentChat),
        JobCategory.exploration =>
          () => context.go(RouteNames.tailor, extra: job),
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.60)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 30,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Row(
              children: [
                Flexible(child: _CategoryBadge(category: job.category)),
                const SizedBox(width: 10),
                if (job.category == JobCategory.ready)
                  Text(
                    '${job.matchScore}% Match',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMuted,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.ink,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    job.company[0],
                    style: const TextStyle(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        job.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: AppColors.ink,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${job.company} • ${job.category == JobCategory.inputNeeded ? job.location : job.salary}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textMuted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.softSurface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(_justificationIcon, size: 15, color: _accentColor),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          job.agentAction.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                            color: _accentColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  job.missingSkills.isNotEmpty
                      ? RichText(
                          text: TextSpan(
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textMuted,
                              height: 1.5,
                              fontFamily: 'Inter',
                            ),
                            children: [
                              TextSpan(
                                text: 'Missing: ${job.missingSkills.join(', ')}. ',
                                style: TextStyle(
                                  color: _accentColor,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              TextSpan(text: job.agentJustification),
                            ],
                          ),
                        )
                      : Text(
                          job.agentJustification,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textMuted,
                            height: 1.5,
                          ),
                        ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _onPrimaryTap(context),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.ink,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _primaryLabel,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                        if (_primaryIcon != null) ...[
                          const SizedBox(width: 8),
                          Icon(_primaryIcon, size: 16),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                _SecondaryAction(
                  isIconOnly: job.category == JobCategory.ready,
                  label: _secondaryLabel,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SecondaryAction extends StatelessWidget {
  const _SecondaryAction({required this.isIconOnly, required this.label});

  final bool isIconOnly;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.scaffold,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () {},
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isIconOnly ? 18 : 20,
            vertical: 16,
          ),
          child: isIconOnly
              ? const Icon(
                  Icons.delete_outline_rounded,
                  size: 20,
                  color: AppColors.textMuted,
                )
              : Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
        ),
      ),
    );
  }
}

class _CategoryBadge extends StatelessWidget {
  const _CategoryBadge({required this.category});

  final JobCategory category;

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg, icon) = switch (category) {
      JobCategory.ready => (
          'Ready to Send',
          AppColors.accent,
          AppColors.ink,
          Icons.check_circle_outline_rounded,
        ),
      JobCategory.inputNeeded => (
          'Needs Your Input',
          AppColors.categoryInput,
          AppColors.ink,
          Icons.error_outline_rounded,
        ),
      JobCategory.exploration => (
          'Strategic Pivot',
          AppColors.categoryExplore,
          Colors.white,
          Icons.star_rounded,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 5),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: fg,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// History tab — vertical timeline
// ---------------------------------------------------------------------------

class _HistoryTab extends StatelessWidget {
  const _HistoryTab({super.key});

  @override
  Widget build(BuildContext context) {
    final items = MockJobs.history;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.screenHorizontalPadding,
        24,
        AppConstants.screenHorizontalPadding,
        140,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) => _HistoryItem(
        data: items[i],
        isLast: i == items.length - 1,
      ),
    );
  }
}

class _HistoryItem extends StatelessWidget {
  const _HistoryItem({required this.data, required this.isLast});

  final Map<String, dynamic> data;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final active = data['active'] as bool;
    final undoable = data['undoable'] as bool;
    final sub = data['sub'] as String;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 50,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    data['time'] as String,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: AppColors.ink,
                      letterSpacing: -0.3,
                    ),
                  ),
                  if (sub.isNotEmpty)
                    Text(
                      sub,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textSoft,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            children: [
              const SizedBox(height: 4),
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active ? AppColors.accent : AppColors.border,
                  boxShadow: active
                      ? [
                          BoxShadow(
                            color: AppColors.accent.withValues(alpha: 0.40),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ]
                      : null,
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.only(top: 4),
                    color: AppColors.border,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 2),
                  Text(
                    data['title'] as String,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    data['desc'] as String,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textMuted,
                      height: 1.45,
                    ),
                  ),
                  if (undoable) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.undo_rounded,
                              size: 13, color: AppColors.ink),
                          SizedBox(width: 5),
                          Text(
                            'Undo Action',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: AppColors.ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
