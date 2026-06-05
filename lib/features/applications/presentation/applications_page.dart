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
import '../../../features/jobs/services/application_quality_meter.dart';
import '../../../shared/widgets/app_header.dart';
import '../services/application_bundle_summary.dart';
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
    final trustReviewCount = allItems
        .where((app) => app.needsTrustReview)
        .length;

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
                  if (trustReviewCount > 0) ...[
                    const SizedBox(height: 12),
                    _TrustReviewBanner(
                      count: trustReviewCount,
                      onTap: () =>
                          notifier.setFilter(ApplicationsFilter.trustReview),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Text(
                    AppStrings.applicationsSubtitle,
                    style: TextStyle(
                      color: brand.textMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _FilterChipsRow(
                    active: state.filter,
                    onChanged: notifier.setFilter,
                  ),
                  const SizedBox(height: 16),
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
                    ...filtered.asMap().entries.map(
                      (entry) =>
                          _TrackerCard(
                                app: entry.value,
                                onTap: () => ApplicationDetailSheet.show(
                                  context,
                                  entry.value,
                                ),
                                onToggleReply: (v) =>
                                    notifier.setGotReply(entry.value.id, v),
                              )
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

class _TrustReviewBanner extends StatelessWidget {
  const _TrustReviewBanner({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final noun = count == 1 ? 'application' : 'applications';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: brand.warning.withValues(alpha: brand.isDark ? 0.18 : 0.11),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: brand.warning.withValues(alpha: 0.34)),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: brand.warning.withValues(
                    alpha: brand.isDark ? 0.22 : 0.14,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: brand.warning.withValues(alpha: 0.38),
                  ),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.verified_user_outlined,
                  size: 18,
                  color: brand.warning,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  '$count $noun need trust verification',
                  style: TextStyle(
                    color: brand.ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    height: 1.25,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.arrow_forward_rounded, size: 18, color: brand.warning),
            ],
          ),
        ),
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

class _TrackerCard extends StatelessWidget {
  const _TrackerCard({
    required this.app,
    required this.onTap,
    required this.onToggleReply,
  });

  final TrackedApplication app;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggleReply;

  String _phaseLine(TrackedApplication a) {
    final fmt = DateFormat('MMM d');
    return switch (a.phase) {
      ApplicationPhase.draft => 'Drafted · ${fmt.format(a.draftedAt)}',
      ApplicationPhase.sent => 'Sent · ${fmt.format(a.sentAt!)}',
      ApplicationPhase.replied =>
        'Replied · ${fmt.format(a.sentAt ?? a.draftedAt)}',
    };
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: brand.surface,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
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
                            app.job.company,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4,
                              color: brand.textMuted,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            app.job.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: brand.ink,
                              letterSpacing: -0.2,
                              height: 1.25,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _PhaseBadge(phase: app.phase),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  _phaseLine(app),
                  style: TextStyle(
                    fontSize: 12.5,
                    color: brand.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                _ApplicationQualityMeter(app: app),
                const SizedBox(height: 10),
                _ApplicationBundleCard(app: app),
                if (app.trustRiskLevel != 'unchecked') ...[
                  const SizedBox(height: 10),
                  _ApplicationTrustTag(app: app),
                ],
                const SizedBox(height: 10),
                Divider(color: brand.border, height: 1),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      Icons.mark_email_read_outlined,
                      size: 16,
                      color: brand.textMuted,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Got a reply',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: brand.ink,
                        ),
                      ),
                    ),
                    Switch.adaptive(
                      value: app.gotReply,
                      onChanged: onToggleReply,
                      activeThumbColor: brand.onAccent,
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

class _ApplicationBundleCard extends StatelessWidget {
  const _ApplicationBundleCard({required this.app});

  final TrackedApplication app;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final bundle = evaluateApplicationBundle(app);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: brand.surfaceMuted.withValues(alpha: brand.isDark ? 0.72 : 0.9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: brand.border.withValues(alpha: 0.75)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.inventory_2_outlined, size: 15, color: brand.ink),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Application bundle',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    color: brand.ink,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
              Text(
                '${bundle.completeCount}/${bundle.totalCount} · ${bundle.statusLabel}',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: bundle.hasBlocker ? brand.warning : brand.success,
                  letterSpacing: -0.05,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final item in bundle.items) _BundleItemChip(item: item),
            ],
          ),
        ],
      ),
    );
  }
}

class _BundleItemChip extends StatelessWidget {
  const _BundleItemChip({required this.item});

  final ApplicationBundleItem item;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final color = item.isBlocking
        ? brand.warning
        : item.isComplete
        ? brand.success
        : brand.textMuted;
    final icon = item.isBlocking
        ? Icons.error_outline_rounded
        : item.isComplete
        ? Icons.check_circle_rounded
        : Icons.radio_button_unchecked_rounded;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: brand.isDark ? 0.16 : 0.1),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12.5, color: color),
          const SizedBox(width: 5),
          Text(
            '${item.label}: ${item.detail}',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
              color: color,
              letterSpacing: -0.05,
            ),
          ),
        ],
      ),
    );
  }
}

class _ApplicationQualityMeter extends StatelessWidget {
  const _ApplicationQualityMeter({required this.app});

  final TrackedApplication app;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final quality = evaluateTrackedApplicationQuality(app);
    final color = _applicationQualityColor(quality.score, brand);
    final reason = quality.reasons.take(2).join(' · ');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: brand.isDark ? 0.12 : 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.speed_rounded, size: 15, color: color),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  quality.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.1,
                    color: brand.ink,
                  ),
                ),
              ),
              Text(
                '${quality.score}%',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: color,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: quality.score / 100,
              minHeight: 5,
              backgroundColor: brand.border.withValues(alpha: 0.55),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          if (reason.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              reason,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: brand.textMuted,
                letterSpacing: -0.05,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

Color _applicationQualityColor(int score, BrandTheme brand) {
  if (score >= 80) return brand.success;
  if (score >= 60) return brand.warning;
  if (score >= 40) return brand.textMuted;
  return brand.danger;
}

class _ApplicationTrustTag extends StatelessWidget {
  const _ApplicationTrustTag({required this.app});

  final TrackedApplication app;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final color = _trustRiskColor(app.trustRiskLevel, brand);
    final icon = _trustRiskIcon(app.trustRiskLevel);
    final label = _trustRiskLabel(app);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: brand.isDark ? 0.18 : 0.11),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.55,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Color _trustRiskColor(String level, BrandTheme brand) => switch (level) {
  'high' => brand.danger,
  'medium' => brand.warning,
  'low' => brand.success,
  _ => brand.textSoft,
};

IconData _trustRiskIcon(String level) => switch (level) {
  'high' => Icons.warning_amber_rounded,
  'medium' => Icons.verified_user_outlined,
  'low' => Icons.shield_outlined,
  _ => Icons.shield_outlined,
};

String _trustRiskLabel(TrackedApplication app) {
  final label = app.trustRiskLabel.trim().isEmpty
      ? 'Not checked'
      : app.trustRiskLabel.trim();

  if (app.trustSignalsCount <= 0) return 'Trust: $label';
  return 'Trust: $label · ${app.trustSignalsCount}';
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
