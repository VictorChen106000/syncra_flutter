import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/router/route_names.dart';
import '../../../core/theme/brand_theme.dart';
import '../../../data/firestore/pipeline_repository.dart';
import '../../../fixtures/mock_jobs.dart';
import '../../../data/models/job.dart';
import '../../../shared/widgets/app_bottom_nav.dart';
import '../../../shared/widgets/app_header.dart';
import '../../../shared/widgets/app_screen.dart';
import '../../../shared/widgets/empty_state_card.dart';
import '../state/jobs_notifier.dart';
import 'widgets/job_action_sheet.dart';

class JobsPage extends ConsumerStatefulWidget {
  const JobsPage({super.key});

  @override
  ConsumerState<JobsPage> createState() => _JobsPageState();
}

class _JobsPageState extends ConsumerState<JobsPage> {
  void _dismiss(Job job) {
    final notifier = ref.read(jobsProvider.notifier);
    notifier.dismiss(job.id, label: job.company);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 3),
          content: Text('${job.company} dismissed'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => notifier.undismiss(job.id),
          ),
        ),
      );
  }

  void _undoSend(Job job) {
    final notifier = ref.read(jobsProvider.notifier);
    notifier.dismiss(job.id, label: job.company);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 4),
          content: Text('Send to ${job.company} undone'),
          action: SnackBarAction(
            label: 'Resend',
            onPressed: () => notifier.undismiss(job.id),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<JobsState>(jobsProvider, (prev, next) {
      if (next.lastMessage == null || next.lastMessage == prev?.lastMessage) {
        return;
      }
      ref.read(jobsProvider.notifier).consumeMessage();
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 3),
            content: Text(next.lastMessage!),
          ),
        );
    });

    final state = ref.watch(jobsProvider);
    final visible = state.pendingCards
        .where((c) => !state.isDismissed(c.job.id))
        .toList();

    return AppScreen(
      showBottomNav: false,
      activeTab: BottomNavTab.agent,
      extendBehindBottomNav: true,
      child: _AgentTimeline(
        cards: visible,
        hasAnyPipeline: state.pendingCards.isNotEmpty,
        onDismiss: _dismiss,
        onUndoSend: _undoSend,
        onMore: (job) => JobActionSheet.show(context, job),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Agent Timeline — the unified single-feed pipeline view.
//
// The agent leads: ready drafts are presented as already-sent (with Undo),
// only items that genuinely need user input or a strategic decision surface
// as actionable cards. No filter tabs, no search — this is a timeline, not
// a search interface.
// ---------------------------------------------------------------------------

class _AgentTimeline extends StatelessWidget {
  const _AgentTimeline({
    required this.cards,
    required this.hasAnyPipeline,
    required this.onDismiss,
    required this.onUndoSend,
    required this.onMore,
  });

  final List<PipelineCard> cards;
  final bool hasAnyPipeline;
  final ValueChanged<Job> onDismiss;
  final ValueChanged<Job> onUndoSend;
  final ValueChanged<Job> onMore;

  @override
  Widget build(BuildContext context) {
    final needs = cards
        .where((c) =>
            c.job.category == JobCategory.inputNeeded ||
            c.job.category == JobCategory.exploration)
        .toList();
    final sent = cards
        .where((c) => c.job.category == JobCategory.ready)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppHeader.tab(
          title: AppStrings.agentPipeline,
          subtitle: _stats(needs.length, sent.length),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppConstants.screenHorizontalPadding,
              8,
              AppConstants.screenHorizontalPadding,
              140,
            ),
            children: [
              if (cards.isEmpty && !hasAnyPipeline)
                EmptyStateCard(
                  icon: Icons.bolt_rounded,
                  title: 'Your agent is idle',
                  body: 'Enable "Today\'s brief" in Settings, then tap '
                      '"Run today\'s brief" on the dashboard. The agent will '
                      'scan roles and drop them here.',
                  actionLabel: 'Open dashboard',
                  onAction: () => context.go(RouteNames.dashboard),
                ),
              if (needs.isNotEmpty) ...[
                _SectionHeader(
                  label: 'Needs you',
                  count: needs.length,
                  accent: AppColors.categoryInputDeep,
                ),
                const SizedBox(height: 12),
                for (var i = 0; i < needs.length; i++)
                  _SwipeDismissible(
                    key: ValueKey('need-${needs[i].job.id}'),
                    onDismissed: () => onDismiss(needs[i].job),
                    child: _JobCard(
                      job: needs[i].job,
                      onDismiss: () => onDismiss(needs[i].job),
                      onMore: () => onMore(needs[i].job),
                    ),
                  )
                      .animate(delay: (i * 60).ms)
                      .fadeIn()
                      .moveY(begin: 16, end: 0),
              ],
              if (sent.isNotEmpty) ...[
                if (needs.isNotEmpty) const SizedBox(height: 8),
                _SectionHeader(
                  label: 'Sent today',
                  count: sent.length,
                  accent: AppColors.success,
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: context.brand.surface,
                    borderRadius:
                        BorderRadius.circular(AppConstants.cardRadius),
                    border: Border.all(
                      color: context.brand.border.withValues(alpha: 0.60),
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (var i = 0; i < sent.length; i++) ...[
                        _SentRow(
                          card: sent[i],
                          onUndo: () => onUndoSend(sent[i].job),
                        ),
                        if (i < sent.length - 1)
                          Divider(
                            height: 1,
                            thickness: 1,
                            color: context.brand.border
                                .withValues(alpha: 0.55),
                          ),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 28),
              _SectionHeader(
                label: 'Recent activity',
                accent: context.brand.textMuted,
              ),
              const SizedBox(height: 16),
              for (var i = 0; i < MockJobs.history.length; i++)
                _HistoryItem(
                  data: MockJobs.history[i],
                  isLast: i == MockJobs.history.length - 1,
                ),
            ],
          ),
        ),
      ],
    );
  }

  String _stats(int needs, int sent) {
    final parts = <String>[];
    if (sent > 0) parts.add('$sent sent today');
    if (needs > 0) parts.add('$needs needs you');
    if (parts.isEmpty) return 'Quiet — no agent activity yet';
    return parts.join(' · ');
  }
}

/// Lightweight section header used to delineate the timeline groups.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.accent, this.count});

  final String label;
  final Color accent;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: accent,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
            color: brand.textMuted,
          ),
        ),
        if (count != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: brand.surfaceMuted,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: brand.ink,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Compact row representing a ready application the agent already queued
/// for sending. Shows when it went out and offers a one-tap Undo.
class _SentRow extends StatelessWidget {
  const _SentRow({required this.card, required this.onUndo});

  final PipelineCard card;
  final VoidCallback onUndo;

  String _timeLabel() {
    final now = DateTime.now();
    final delta = now.difference(card.createdAt);
    if (delta.inMinutes < 1) return 'just now';
    if (delta.inMinutes < 60) return '${delta.inMinutes}m ago';
    if (delta.inHours < 24) return '${delta.inHours}h ago';
    final hh = card.createdAt.hour.toString().padLeft(2, '0');
    final mm = card.createdAt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final job = card.job;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: brand.ink,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Text(
              job.company[0],
              style: TextStyle(
                color: brand.accent,
                fontWeight: FontWeight.w900,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      size: 13,
                      color: brand.accentBright,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'SENT · ${_timeLabel()}',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.1,
                        color: brand.textMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  job.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: brand.ink,
                    letterSpacing: -0.1,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  job.company,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: brand.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: brand.surfaceMuted,
            borderRadius: BorderRadius.circular(99),
            child: InkWell(
              onTap: onUndo,
              borderRadius: BorderRadius.circular(99),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.undo_rounded, size: 13, color: brand.ink),
                    const SizedBox(width: 5),
                    Text(
                      'Undo',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: brand.ink,
                      ),
                    ),
                  ],
                ),
              ),
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

/// Wraps a child in a swipe-left-to-dismiss gesture (built-in Flutter
/// [Dismissible]). Reveals a red trash background as the user drags.
class _SwipeDismissible extends StatelessWidget {
  const _SwipeDismissible({
    super.key,
    required this.child,
    required this.onDismissed,
  });

  final Widget child;
  final VoidCallback onDismissed;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Dismissible(
      key: ValueKey('dismiss-${(key as ValueKey).value}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDismissed(),
      background: const SizedBox.shrink(),
      secondaryBackground: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.only(right: 28),
        alignment: Alignment.centerRight,
        decoration: BoxDecoration(
          color: brand.danger.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: const [
            Icon(Icons.archive_rounded, color: Colors.white, size: 22),
            SizedBox(width: 10),
            Text(
              'Dismiss',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 14,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
      child: child,
    );
  }
}

/// Animated circular match-score ring. Uses [TweenAnimationBuilder] to
/// sweep the arc from 0 to [score] and counts the number up in sync.
class _MatchRing extends StatelessWidget {
  const _MatchRing({required this.score, required this.color});

  final int score;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: score / 100),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, t, _) {
        return SizedBox(
          width: 46,
          height: 46,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: const Size(46, 46),
                painter: _RingPainter(
                  progress: t,
                  trackColor: brand.border.withValues(alpha: 0.6),
                  ringColor: color,
                ),
              ),
              Text(
                '${(t * 100).round()}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: brand.ink,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.trackColor,
    required this.ringColor,
  });

  final double progress;
  final Color trackColor;
  final Color ringColor;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 4.0;
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = math.min(size.width, size.height) / 2 - stroke / 2;

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = trackColor;
    canvas.drawCircle(center, radius, trackPaint);

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = ringColor;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress.clamp(0.0, 1.0),
      false,
      ringPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress ||
      old.ringColor != ringColor ||
      old.trackColor != trackColor;
}

class _JobCard extends StatefulWidget {
  const _JobCard({
    required this.job,
    required this.onDismiss,
    required this.onMore,
  });

  final Job job;
  final VoidCallback onDismiss;
  final VoidCallback onMore;

  @override
  State<_JobCard> createState() => _JobCardState();
}

class _JobCardState extends State<_JobCard> {
  Color _accentColor(BrandTheme brand) => switch (widget.job.category) {
        JobCategory.ready => brand.ink,
        JobCategory.inputNeeded => AppColors.categoryInputDeep,
        JobCategory.exploration => AppColors.categoryExploreDeep,
      };

  IconData get _justificationIcon => switch (widget.job.category) {
        JobCategory.ready => Icons.auto_awesome_rounded,
        JobCategory.inputNeeded => Icons.error_outline_rounded,
        JobCategory.exploration => Icons.star_rounded,
      };

  String get _primaryLabel => switch (widget.job.category) {
        JobCategory.ready => 'Send',
        JobCategory.inputNeeded => 'Open chat',
        JobCategory.exploration => 'Draft',
      };

  IconData get _primaryIcon => switch (widget.job.category) {
        JobCategory.ready => Icons.arrow_forward_rounded,
        JobCategory.inputNeeded => Icons.chat_bubble_outline_rounded,
        JobCategory.exploration => Icons.auto_awesome_rounded,
      };

  // Agentic flow: every pipeline interaction routes to the chatbot — no
  // secondary review/tailor/data-viz pages. The agent owns the thread.
  VoidCallback _onPrimaryTap(BuildContext context) =>
      () => context.go(RouteNames.agentChat);

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final accentColor = _accentColor(brand);
    final job = widget.job;
    final isInputNeeded = job.category == JobCategory.inputNeeded;
    final isStrategic = job.category == JobCategory.exploration;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        border: Border.all(color: brand.border.withValues(alpha: 0.60)),
        boxShadow: [
          BoxShadow(
            color: brand.shadow,
            blurRadius: 24,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Colored left accent stripe — category at a glance.
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 5,
            child: Container(color: accentColor),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Tap anywhere on the card body to open the agent thread.
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _onPrimaryTap(context),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 18, 18, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Flexible(
                                  child: _CategoryBadge(category: job.category),
                                ),
                                const Spacer(),
                                _MatchRing(
                                  score: job.matchScore,
                                  color: accentColor,
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
                                    color: brand.ink,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    job.company[0],
                                    style: TextStyle(
                                      color: brand.accent,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 17,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        job.title,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 16,
                                          color: brand.ink,
                                          letterSpacing: -0.2,
                                          height: 1.2,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${job.company} · ${isInputNeeded ? job.location : job.salary}',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          color: brand.textMuted,
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
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 18, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(_justificationIcon,
                                    size: 13, color: accentColor),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    job.agentAction.toUpperCase(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.4,
                                      color: accentColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            job.missingSkills.isNotEmpty
                                ? RichText(
                                    text: TextSpan(
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: brand.textMuted,
                                        height: 1.5,
                                        fontFamily: 'Inter',
                                      ),
                                      children: [
                                        TextSpan(
                                          text:
                                              'Missing: ${job.missingSkills.join(', ')}. ',
                                          style: TextStyle(
                                            color: accentColor,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        TextSpan(
                                          text: job.agentJustification,
                                        ),
                                      ],
                                    ),
                                  )
                                : Text(
                                    job.agentJustification,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: brand.textMuted,
                                      height: 1.5,
                                    ),
                                  ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 18, 18),
                child: isStrategic
                    ? Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _onPrimaryTap(context),
                              icon: const Icon(
                                Icons.trending_up_rounded,
                                size: 16,
                              ),
                              label: const Text(
                                'Pursue',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                ),
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: accentColor,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: widget.onDismiss,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: brand.textMuted,
                                side: BorderSide(color: brand.border),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text(
                                'Pass',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _onPrimaryTap(context),
                              icon: Icon(_primaryIcon, size: 16),
                              label: Text(
                                _primaryLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                ),
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: brand.ink,
                                foregroundColor: brand.inkInverse,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          _IconActionButton(
                            icon: Icons.more_horiz_rounded,
                            semanticLabel: 'More actions',
                            onTap: widget.onMore,
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Minimalist square icon-only button — pairs alongside the primary CTA.
class _IconActionButton extends StatelessWidget {
  const _IconActionButton({
    required this.icon,
    required this.onTap,
    required this.semanticLabel,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Semantics(
      label: semanticLabel,
      button: true,
      child: Material(
        color: brand.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          excludeFromSemantics: true,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Icon(icon, size: 20, color: brand.textMuted),
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
    final brand = context.brand;
    final (label, bg, fg, icon) = switch (category) {
      JobCategory.ready => (
          'Ready to Send',
          brand.accent,
          brand.onAccent,
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
// Activity feed item — used inline in the timeline's "Recent activity" group.
// ---------------------------------------------------------------------------

class _HistoryItem extends StatelessWidget {
  const _HistoryItem({required this.data, required this.isLast});

  final Map<String, dynamic> data;
  final bool isLast;

  String _timeLabel() {
    final time = data['time'] as String;
    final sub = (data['sub'] as String?) ?? '';
    return sub.isEmpty ? time : '$time $sub';
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final active = data['active'] as bool;
    final undoable = data['undoable'] as bool;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 16,
            child: Column(
              children: [
                const SizedBox(height: 8),
                _TimelineNode(active: active),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            brand.border.withValues(alpha: 0.85),
                            brand.border.withValues(alpha: 0.25),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 26),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _timeLabel().toUpperCase(),
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.4,
                      color: active ? brand.ink : brand.textSoft,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    data['title'] as String,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: brand.ink,
                      letterSpacing: -0.2,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    data['desc'] as String,
                    style: TextStyle(
                      fontSize: 13,
                      color: brand.textMuted,
                      height: 1.55,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (undoable) ...[
                    const SizedBox(height: 10),
                    _TimelineUndo(
                      onTap: () {
                        ScaffoldMessenger.of(context)
                          ..clearSnackBars()
                          ..showSnackBar(
                            const SnackBar(
                              content: Text('Action undone'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                      },
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

/// Small accent-green dot. Active dots get a soft glow plus a pulsing ring;
/// done dots sit quiet as a hairline-bordered circle.
class _TimelineNode extends StatelessWidget {
  const _TimelineNode({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    const size = 10.0;

    final dot = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? brand.accent : brand.surface,
        border: Border.all(
          color: active ? brand.accent : brand.border,
          width: 2,
        ),
        boxShadow: active
            ? [
                BoxShadow(
                  color: brand.accent.withValues(alpha: 0.30),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
    );

    if (!active) return dot;

    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: brand.accent.withValues(alpha: 0.45),
          ),
        )
            .animate(onPlay: (c) => c.repeat())
            .scaleXY(
              duration: 1600.ms,
              begin: 1.0,
              end: 2.2,
              curve: Curves.easeOut,
            )
            .fadeOut(duration: 1600.ms),
        dot,
      ],
    );
  }
}

/// Quiet text-button-style undo — no border, subtle hover, sits flush with
/// the timeline column rather than competing with it.
class _TimelineUndo extends StatelessWidget {
  const _TimelineUndo({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 6,
            vertical: 4,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.undo_rounded,
                size: 13,
                color: brand.textMuted,
              ),
              const SizedBox(width: 6),
              Text(
                'Undo',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                  color: brand.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
