import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/router/route_names.dart';
import '../../../core/theme/brand_theme.dart';
import '../../../data/models/tracked_application.dart';
import '../../../shared/widgets/app_header.dart';
import '../../../shared/widgets/empty_state_card.dart';
import '../state/applications_notifier.dart';
import 'widgets/application_detail_sheet.dart';

class ApplicationsPage extends ConsumerWidget {
  const ApplicationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    ref.listen<ApplicationsState>(applicationsProvider, (prev, next) {
      if (next.lastMessage == null || next.lastMessage == prev?.lastMessage) {
        return;
      }
      ref.read(applicationsProvider.notifier).consumeMessage();
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(next.lastMessage!)));
    });

    final state = ref.watch(applicationsProvider);
    final notifier = ref.read(applicationsProvider.notifier);
    final filtered = state.filtered;
    final allItems = state.items;

    return Scaffold(
      backgroundColor: brand.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            AppHeader.page(
              title: AppStrings.applicationsTitle,
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
                  _SummaryStrip(apps: allItems),
                  const SizedBox(height: 18),
                  _FilterChipsRow(
                    active: state.filter,
                    onChanged: notifier.setFilter,
                  ),
                  const SizedBox(height: 18),
                  if (filtered.isEmpty)
                    allItems.isEmpty
                        ? EmptyStateCard(
                            icon: Icons.send_rounded,
                            title: 'No applications yet',
                            body:
                                'Open the chat to ask the agent to apply to a role, '
                                'or browse roles in your pipeline.',
                            actionLabel: 'Open chat',
                            onAction: () => context.go(RouteNames.agentChat),
                          )
                        : const _EmptyFiltered()
                  else
                    for (var i = 0; i < filtered.length; i++)
                      _TimelineEntry(
                            app: filtered[i],
                            isFirst: i == 0,
                            isLast: i == filtered.length - 1,
                            onTap: () => ApplicationDetailSheet.show(
                              context,
                              filtered[i],
                            ),
                          )
                          .animate(delay: (i * 60).ms)
                          .fadeIn()
                          .moveY(begin: 14, end: 0),
                ],
              ),
            ),
          ],
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
    final brand = context.brand;
    int countOf(ApplicationPhase p) => apps.where((a) => a.phase == p).length;
    final cells = <(int, String, Color, Color)>[
      (
        countOf(ApplicationPhase.draft),
        'Drafts',
        brand.surfaceMuted,
        brand.ink,
      ),
      (countOf(ApplicationPhase.sent), 'Sent', brand.ink, brand.accent),
      (
        countOf(ApplicationPhase.replied),
        'Replied',
        brand.accent,
        brand.onAccent,
      ),
    ];
    return Row(
      children: [
        for (var i = 0; i < cells.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: _SummaryTile(
              count: cells[i].$1,
              label: cells[i].$2,
              background: cells[i].$3,
              foreground: cells[i].$4,
            ),
          ),
        ],
      ],
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.count,
    required this.label,
    required this.background,
    required this.foreground,
  });

  final int count;
  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: brand.border.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$count',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: foreground,
              height: 1.0,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
              color: foreground.withValues(alpha: 0.75),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChipsRow extends StatelessWidget {
  const _FilterChipsRow({required this.active, required this.onChanged});

  final ApplicationsFilter active;
  final ValueChanged<ApplicationsFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final f in ApplicationsFilter.values) ...[
            _FilterChip(
              label: f.label,
              active: active == f,
              onTap: () => onChanged(f),
            ),
            const SizedBox(width: 8),
          ],
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
    final brand = context.brand;
    return Material(
      color: active ? brand.ink : brand.surface,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: active ? Colors.transparent : brand.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: active ? brand.inkInverse : brand.ink,
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
    final brand = context.brand;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: brand.border),
      ),
      child: Column(
        children: [
          Icon(Icons.filter_alt_off_outlined, color: brand.textMuted, size: 26),
          const SizedBox(height: 8),
          Text(
            'No applications match this filter',
            style: TextStyle(fontWeight: FontWeight.w800, color: brand.ink),
          ),
        ],
      ),
    );
  }
}

String _phaseLine(TrackedApplication a) {
  final fmt = DateFormat('MMM d');
  return switch (a.phase) {
    ApplicationPhase.draft => 'Drafted · ${fmt.format(a.draftedAt)}',
    ApplicationPhase.sent => 'Sent · ${fmt.format(a.sentAt!)}',
    ApplicationPhase.replied =>
      'Replied · ${fmt.format(a.sentAt ?? a.draftedAt)}',
  };
}

Color _nodeColor(ApplicationPhase phase, BrandTheme brand) => switch (phase) {
  ApplicationPhase.draft => brand.textSoft,
  ApplicationPhase.sent => brand.accent,
  ApplicationPhase.replied => brand.success,
};

/// One entry in the tracker timeline: a coloured node on a continuous rail,
/// with the application card to its right. [isFirst]/[isLast] trim the rail so
/// the connecting line doesn't overshoot the ends.
class _TimelineEntry extends StatelessWidget {
  const _TimelineEntry({
    required this.app,
    required this.isFirst,
    required this.isLast,
    required this.onTap,
  });

  final TrackedApplication app;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Rail(
            color: brand.border,
            nodeColor: _nodeColor(app.phase, brand),
            ringColor: brand.bg,
            isFirst: isFirst,
            isLast: isLast,
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(left: 12, bottom: isLast ? 0 : 12),
              child: Material(
                color: brand.surface,
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: brand.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    app.job.company.toUpperCase(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.6,
                                      color: brand.textMuted,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    app.job.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 15.5,
                                      fontWeight: FontWeight.w800,
                                      color: brand.ink,
                                      letterSpacing: -0.2,
                                      height: 1.25,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            _PhaseBadge(phase: app.phase),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _phaseLine(app),
                          style: TextStyle(
                            fontSize: 12.5,
                            color: brand.textMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({
    required this.color,
    required this.nodeColor,
    required this.ringColor,
    required this.isFirst,
    required this.isLast,
  });

  final Color color;
  final Color nodeColor;
  final Color ringColor;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Stub from the top edge down to the node, aligned with the card's
          // company line. Hidden on the first entry.
          Container(
            width: 2,
            height: 16,
            color: isFirst ? Colors.transparent : color,
          ),
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: ringColor,
              shape: BoxShape.circle,
              border: Border.all(color: nodeColor, width: 2.5),
            ),
            child: Center(
              child: Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: nodeColor,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          // Fills the rest of the row height (including the gap to the next
          // entry) so the line is continuous. Hidden on the last entry.
          Expanded(
            child: Container(
              width: 2,
              color: isLast ? Colors.transparent : color,
            ),
          ),
        ],
      ),
    );
  }
}

class _PhaseBadge extends StatelessWidget {
  const _PhaseBadge({required this.phase});

  final ApplicationPhase phase;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final (bg, fg) = switch (phase) {
      ApplicationPhase.draft => (brand.surfaceMuted, brand.ink),
      ApplicationPhase.sent => (brand.ink, brand.accent),
      ApplicationPhase.replied => (brand.accent, brand.onAccent),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(
          color: phase == ApplicationPhase.draft
              ? brand.border
              : Colors.transparent,
        ),
      ),
      child: Text(
        phase.label.toUpperCase(),
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.2,
          color: fg,
        ),
      ),
    );
  }
}
