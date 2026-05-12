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
  final Set<String> _dismissedIds = {};

  List<Job> get _filteredQueue {
    final all = [
      ...MockJobs.ready,
      ...MockJobs.inputNeeded,
      ...MockJobs.exploration,
    ];
    return all.where((j) {
      if (_dismissedIds.contains(j.id)) return false;
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

  void _dismiss(Job job) {
    setState(() => _dismissedIds.add(job.id));
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          content: Text('${job.company} dismissed'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () =>
                setState(() => _dismissedIds.remove(job.id)),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return AppScreen(
      showBottomNav: false,
      activeTab: BottomNavTab.agent,
      extendBehindBottomNav: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppHeader.tab(
            title: AppStrings.agentPipeline,
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
                      onDismiss: _dismiss,
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
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.1,
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
    required this.onDismiss,
  });

  final String query;
  final _Filter filter;
  final List<Job> jobs;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<_Filter> onFilterChanged;
  final ValueChanged<Job> onDismiss;

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
        _FilterSearchRow(
          query: query,
          filter: filter,
          onQueryChanged: onQueryChanged,
          onFilterChanged: onFilterChanged,
        ),
        const SizedBox(height: 20),
        if (jobs.isEmpty)
          const _EmptyResults()
        else
          ...jobs.asMap().entries.map((entry) {
            final job = entry.value;
            return _JobCard(
              key: ValueKey(job.id),
              job: job,
              onDismiss: () => onDismiss(job),
            )
                .animate(delay: (entry.key * 60).ms)
                .fadeIn()
                .moveY(begin: 16, end: 0);
          }),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Filter chips + inline expanding search (single row)
// ---------------------------------------------------------------------------

class _FilterSearchRow extends StatefulWidget {
  const _FilterSearchRow({
    required this.query,
    required this.filter,
    required this.onQueryChanged,
    required this.onFilterChanged,
  });

  final String query;
  final _Filter filter;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<_Filter> onFilterChanged;

  @override
  State<_FilterSearchRow> createState() => _FilterSearchRowState();
}

class _FilterSearchRowState extends State<_FilterSearchRow> {
  late bool _searching = widget.query.isNotEmpty;
  late final TextEditingController _controller =
      TextEditingController(text: widget.query);
  final FocusNode _focusNode = FocusNode();

  @override
  void didUpdateWidget(covariant _FilterSearchRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.query != _controller.text) {
      _controller.text = widget.query;
      _controller.selection =
          TextSelection.collapsed(offset: widget.query.length);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _enterSearch() {
    setState(() => _searching = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  void _exitSearch() {
    _controller.clear();
    widget.onQueryChanged('');
    _focusNode.unfocus();
    setState(() => _searching = false);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 240),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          return FadeTransition(
            opacity: animation,
            child: SizeTransition(
              axis: Axis.horizontal,
              sizeFactor: animation,
              axisAlignment: 1,
              child: child,
            ),
          );
        },
        child: _searching
            ? _SearchField(
                key: const ValueKey('search'),
                controller: _controller,
                focusNode: _focusNode,
                onChanged: widget.onQueryChanged,
                onClose: _exitSearch,
              )
            : _FilterChipsRow(
                key: const ValueKey('chips'),
                active: widget.filter,
                onChanged: widget.onFilterChanged,
                onSearchTap: _enterSearch,
              ),
      ),
    );
  }
}

class _FilterChipsRow extends StatelessWidget {
  const _FilterChipsRow({
    super.key,
    required this.active,
    required this.onChanged,
    required this.onSearchTap,
  });

  final _Filter active;
  final ValueChanged<_Filter> onChanged;
  final VoidCallback onSearchTap;

  static const _filters = [
    (_Filter.all, 'All'),
    (_Filter.ready, 'Ready'),
    (_Filter.input, 'Needs Input'),
    (_Filter.strategic, 'Strategic'),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: _filters.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final (f, label) = _filters[i];
              return _FilterChip(
                label: label,
                active: active == f,
                onTap: () => onChanged(f),
              );
            },
          ),
        ),
        const SizedBox(width: 10),
        _IconCircleButton(
          icon: Icons.search_rounded,
          onTap: onSearchTap,
        ),
      ],
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onClose,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.search_rounded,
              size: 18, color: AppColors.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
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
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                isCollapsed: true,
              ),
            ),
          ),
          InkResponse(
            onTap: onClose,
            radius: 22,
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(
                Icons.close_rounded,
                size: 18,
                color: AppColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IconCircleButton extends StatelessWidget {
  const _IconCircleButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: const CircleBorder(side: BorderSide(color: AppColors.border)),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, size: 18, color: AppColors.ink),
        ),
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
              fontSize: 13,
              fontWeight: FontWeight.w700,
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
          SizedBox(height: 12),
          Text(
            'Nothing matched',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: AppColors.ink,
              letterSpacing: -0.1,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Try a different search or clear the filter.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.4,
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

class _JobCard extends StatefulWidget {
  const _JobCard({super.key, required this.job, required this.onDismiss});

  final Job job;
  final VoidCallback onDismiss;

  @override
  State<_JobCard> createState() => _JobCardState();
}

class _JobCardState extends State<_JobCard> {
  bool _expanded = false;

  Color get _accentColor => switch (widget.job.category) {
        JobCategory.ready => AppColors.ink,
        JobCategory.inputNeeded => AppColors.categoryInputDeep,
        JobCategory.exploration => AppColors.categoryExploreDeep,
      };

  IconData get _justificationIcon => switch (widget.job.category) {
        JobCategory.ready => Icons.auto_awesome_rounded,
        JobCategory.inputNeeded => Icons.error_outline_rounded,
        JobCategory.exploration => Icons.star_rounded,
      };

  String get _primaryLabel => switch (widget.job.category) {
        JobCategory.ready => 'Export Application',
        JobCategory.inputNeeded => 'Reply in Chat',
        JobCategory.exploration => 'Generate Draft',
      };

  IconData? get _primaryIcon => switch (widget.job.category) {
        JobCategory.ready => null,
        JobCategory.inputNeeded => Icons.send_rounded,
        JobCategory.exploration => Icons.star_rounded,
      };

  String get _secondaryLabel => switch (widget.job.category) {
        JobCategory.ready => '',
        JobCategory.inputNeeded => 'Skip',
        JobCategory.exploration => 'Ignore',
      };

  VoidCallback _onPrimaryTap(BuildContext context) =>
      switch (widget.job.category) {
        JobCategory.ready =>
          () => context.go(RouteNames.review, extra: widget.job),
        JobCategory.inputNeeded => () => context.go(RouteNames.agentChat),
        JobCategory.exploration =>
          () => context.go(RouteNames.tailor, extra: widget.job),
      };

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    final job = widget.job;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.60)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 24,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Always-visible summary ─────────────────────────────────────
          InkWell(
            onTap: _toggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(child: _CategoryBadge(category: job.category)),
                      const Spacer(),
                      if (job.category == JobCategory.ready)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Text(
                            '${job.matchScore}% Match',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ),
                      AnimatedRotation(
                        duration: const Duration(milliseconds: 220),
                        turns: _expanded ? 0.5 : 0,
                        child: const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 22,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
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
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                                color: AppColors.ink,
                                letterSpacing: -0.2,
                                height: 1.2,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${job.company} · ${job.category == JobCategory.inputNeeded ? job.location : job.salary}',
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
                ],
              ),
            ),
          ),

          // ── Collapsible detail ─────────────────────────────────────────
          AnimatedSize(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.softSurface,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(_justificationIcon,
                                  size: 14, color: _accentColor),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  job.agentAction.toUpperCase(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.0,
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
                                        text:
                                            'Missing: ${job.missingSkills.join(', ')}. ',
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
                  )
                : const SizedBox(width: double.infinity, height: 0),
          ),

          // ── Action row ─────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _onPrimaryTap(context),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.ink,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            _primaryLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
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
                const SizedBox(width: 10),
                _SecondaryAction(
                  isIconOnly: job.category == JobCategory.ready,
                  label: _secondaryLabel,
                  onTap: widget.onDismiss,
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
  const _SecondaryAction({
    required this.isIconOnly,
    required this.label,
    required this.onTap,
  });

  final bool isIconOnly;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.scaffold,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isIconOnly ? 16 : 18,
            vertical: 14,
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
                    fontWeight: FontWeight.w700,
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: fg,
                letterSpacing: 0.8,
              ),
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
          // Timeline rail
          SizedBox(
            width: 16,
            child: Column(
              children: [
                const SizedBox(height: 6),
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: active ? AppColors.accent : AppColors.surface,
                    border: Border.all(
                      color: active ? AppColors.accent : AppColors.border,
                      width: 2,
                    ),
                    boxShadow: active
                        ? [
                            BoxShadow(
                              color: AppColors.accent.withValues(alpha: 0.30),
                              blurRadius: 6,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: AppColors.border.withValues(alpha: 0.6),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          // Content
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          data['title'] as String,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: AppColors.ink,
                            letterSpacing: -0.1,
                            height: 1.2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        data['time'] as String,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                  if (sub.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      sub,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSoft,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    data['desc'] as String,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textMuted,
                      height: 1.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (undoable) ...[
                    const SizedBox(height: 10),
                    Material(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        onTap: () {
                          ScaffoldMessenger.of(context)
                            ..clearSnackBars()
                            ..showSnackBar(
                              const SnackBar(
                                behavior: SnackBarBehavior.floating,
                                content: Text('Action undone'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.undo_rounded,
                                  size: 13, color: AppColors.ink),
                              SizedBox(width: 6),
                              Text(
                                'Undo',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.ink,
                                ),
                              ),
                            ],
                          ),
                        ),
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
