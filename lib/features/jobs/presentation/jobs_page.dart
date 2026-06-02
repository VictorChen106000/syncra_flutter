import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/router/route_names.dart';
import '../../../core/theme/brand_theme.dart';
import '../../../data/firestore/pipeline_repository.dart';
import '../../../data/models/job.dart';
import '../../../shared/widgets/app_bottom_nav.dart';
import '../../../shared/widgets/app_header.dart';
import '../../../shared/widgets/app_screen.dart';
import '../../../shared/widgets/empty_state_card.dart';
import '../../agent/state/passive_agent_notifier.dart';
import '../../agent_chat/state/agent_chat_notifier.dart';
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
    final agentHasRun =
        ref.watch(passiveAgentProvider.select((s) => s.lastBriefAt != null));

    return AppScreen(
      showBottomNav: false,
      activeTab: BottomNavTab.agent,
      extendBehindBottomNav: true,
      child: _AgentTimeline(
        cards: visible,
        hasAnyPipeline: state.pendingCards.isNotEmpty,
        agentHasRun: agentHasRun,
        onDismiss: _dismiss,
        onUndoSend: _undoSend,
        onMore: (job) => JobActionSheet.show(context, job),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Agent Timeline — the pipeline split into two swipeable pages.
//
// The agent leads: ready drafts land in "Sent today" (already actioned, with
// Undo); only items that genuinely need user input or a strategic decision
// surface in "Needs you". A segmented control in the header switches between
// the two, and the pages are swipeable. No search — this is a timeline, not a
// search interface.
// ---------------------------------------------------------------------------

class _AgentTimeline extends StatefulWidget {
  const _AgentTimeline({
    required this.cards,
    required this.hasAnyPipeline,
    required this.agentHasRun,
    required this.onDismiss,
    required this.onUndoSend,
    required this.onMore,
  });

  final List<PipelineCard> cards;
  final bool hasAnyPipeline;
  final bool agentHasRun;
  final ValueChanged<Job> onDismiss;
  final ValueChanged<Job> onUndoSend;
  final ValueChanged<Job> onMore;

  @override
  State<_AgentTimeline> createState() => _AgentTimelineState();
}

class _AgentTimelineState extends State<_AgentTimeline>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  // We default to "Needs you", but the first time real cards arrive we jump to
  // whichever page actually has something — landing on an empty page while the
  // other is full feels broken. Done exactly once.
  bool _syncedInitialTab = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final needs = widget.cards
        .where((c) =>
            c.job.category == JobCategory.inputNeeded ||
            c.job.category == JobCategory.exploration)
        .toList();
    final sent = widget.cards
        .where((c) => c.job.category == JobCategory.ready)
        .toList();

    // Whole pipeline empty → the three-flavor onboarding/empty surface, with
    // no segmented control (there's nothing to switch between).
    if (widget.cards.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppHeader.tab(
            title: AppStrings.agentPipeline,
            subtitle: 'Quiet — no agent activity yet',
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppConstants.screenHorizontalPadding,
                8,
                AppConstants.screenHorizontalPadding,
                140,
              ),
              children: [_buildEmptyState(context)],
            ),
          ),
        ],
      );
    }

    if (!_syncedInitialTab) {
      _syncedInitialTab = true;
      final wantIndex = needs.isNotEmpty ? 0 : 1;
      if (_tab.index != wantIndex) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _tab.index = wantIndex;
        });
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppHeader.tab(
          title: AppStrings.agentPipeline,
          bottom: _SegmentedControl(
            controller: _tab,
            segments: [
              _SegmentData(
                label: 'Needs you',
                count: needs.length,
                accent: context.brand.ink,
              ),
              _SegmentData(
                label: 'Sent today',
                count: sent.length,
                accent: context.brand.accentBright,
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: [
              _NeedsPage(
                needs: needs,
                onDismiss: widget.onDismiss,
                onMore: widget.onMore,
              ),
              _SentPage(
                sent: sent,
                onUndoSend: widget.onUndoSend,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    // Three flavors so the surface explains *why* it's empty:
    //   1. Agent has never run → onboard the user to kick off the brief.
    //   2. Agent ran, found nothing → reassure, suggest broadening criteria.
    //   3. Agent ran, all surfaced cards dismissed → "inbox zero" praise.
    if (!widget.agentHasRun) {
      return EmptyStateCard(
        icon: Icons.bolt_rounded,
        title: 'Your agent is idle',
        body: 'Enable "Today\'s brief" in Settings, then tap '
            '"Run today\'s brief" on the dashboard. The agent will '
            'scan roles and drop them here.',
        actionLabel: 'Open dashboard',
        onAction: () => context.go(RouteNames.dashboard),
      );
    }
    if (!widget.hasAnyPipeline) {
      return EmptyStateCard(
        icon: Icons.search_rounded,
        title: 'No new roles right now',
        body: 'The agent scanned but didn\'t find any strong matches. '
            'Try broadening your criteria in Settings, or ask the agent '
            'to explore a different direction.',
        actionLabel: 'Ask the agent',
        onAction: () => context.go(RouteNames.agentChat),
      );
    }
    return EmptyStateCard(
      icon: Icons.check_circle_outline_rounded,
      title: 'You\'re all caught up',
      body: 'Every role the agent surfaced has been handled. '
          'The next brief will refill this list.',
      actionLabel: 'Back to dashboard',
      onAction: () => context.go(RouteNames.dashboard),
    );
  }
}

// ---------------------------------------------------------------------------
// Pages — each tab is its own independently-scrolling list.
// ---------------------------------------------------------------------------

/// "Needs you" page — input-needed and strategic-exploration items rendered as
/// borderless notification rows. Tap a row to open the agent thread, swipe to
/// dismiss, or use the trailing overflow for the rest.
class _NeedsPage extends ConsumerWidget {
  const _NeedsPage({
    required this.needs,
    required this.onDismiss,
    required this.onMore,
  });

  final List<PipelineCard> needs;
  final ValueChanged<Job> onDismiss;
  final ValueChanged<Job> onMore;

  static IconData _icon(JobCategory c) => switch (c) {
        JobCategory.inputNeeded => Icons.error_outline_rounded,
        JobCategory.exploration => Icons.auto_awesome_rounded,
        JobCategory.ready => Icons.check_circle_rounded,
      };

  static Color _iconColor(BrandTheme brand, JobCategory c) => switch (c) {
        JobCategory.inputNeeded => brand.warning,
        JobCategory.exploration => brand.ink,
        JobCategory.ready => brand.success,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.screenHorizontalPadding,
        4,
        AppConstants.screenHorizontalPadding,
        140,
      ),
      children: [
        if (needs.isEmpty)
          const _PageHint(
            icon: Icons.check_circle_outline_rounded,
            title: 'Nothing needs you',
            body: 'The agent has everything it needs right now. '
                'Check "Sent today" or wait for the next brief.',
          )
        else
          for (var i = 0; i < needs.length; i++)
            _SwipeDismissible(
              key: ValueKey('need-${needs[i].job.id}'),
              onDismissed: () => onDismiss(needs[i].job),
              child: _row(context, ref, needs[i].job, i < needs.length - 1),
            )
                .animate(delay: (i * 60).ms)
                .fadeIn()
                .moveY(begin: 12, end: 0),
      ],
    );
  }

  Widget _row(
    BuildContext context,
    WidgetRef ref,
    Job job,
    bool showDivider,
  ) {
    final brand = context.brand;
    final isInputNeeded = job.category == JobCategory.inputNeeded;
    return _NotificationRow(
      leadingIcon: _icon(job.category),
      leadingColor: _iconColor(brand, job.category),
      kicker: job.agentAction.toUpperCase(),
      tag: job.matchLabel,
      tagColor: isInputNeeded ? brand.ink : brand.textMuted,
      title: job.title,
      subtitle: '${job.company} · ${isInputNeeded ? job.location : job.salary}',
      message: _message(brand, job),
      showDivider: showDivider,
      trailing: _IconActionButton(
        icon: Icons.more_horiz_rounded,
        semanticLabel: 'More actions',
        onTap: () => onMore(job),
      ),
      onTap: () {
        ref.read(agentChatProvider.notifier).openJobThread(job);
        context.go(RouteNames.agentChat);
      },
    );
  }

  Widget _message(BrandTheme brand, Job job) {
    final base = TextStyle(fontSize: 13, color: brand.textMuted, height: 1.45);
    if (job.missingSkills.isEmpty) {
      return Text(
        job.agentJustification,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: base,
      );
    }
    return RichText(
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: base.copyWith(fontFamily: 'Inter'),
        children: [
          TextSpan(
            text: 'Missing: ${job.missingSkills.join(', ')}. ',
            style: TextStyle(color: brand.ink, fontWeight: FontWeight.w800),
          ),
          TextSpan(text: job.agentJustification),
        ],
      ),
    );
  }
}

/// "Sent today" page — the grouped list of ready applications the agent
/// queued, each with a one-tap Undo.
class _SentPage extends StatelessWidget {
  const _SentPage({required this.sent, required this.onUndoSend});

  final List<PipelineCard> sent;
  final ValueChanged<Job> onUndoSend;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.screenHorizontalPadding,
        4,
        AppConstants.screenHorizontalPadding,
        140,
      ),
      children: [
        if (sent.isEmpty)
          const _PageHint(
            icon: Icons.outbox_rounded,
            title: 'Nothing sent yet',
            body: 'When the agent queues applications, they\'ll appear '
                'here as already sent — with an Undo.',
          )
        else
          for (var i = 0; i < sent.length; i++)
            _SentRow(
              card: sent[i],
              onUndo: () => onUndoSend(sent[i].job),
              showDivider: i < sent.length - 1,
            ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Segmented control — premium pill toggle wired to the [TabController]. The
// active "thumb" tracks the page swipe continuously (driven by the
// controller's animation), so dragging between pages drags the indicator too.
// ---------------------------------------------------------------------------

class _SegmentData {
  const _SegmentData({
    required this.label,
    required this.count,
    required this.accent,
  });

  final String label;
  final int count;
  final Color accent;
}

class _SegmentedControl extends StatelessWidget {
  const _SegmentedControl({required this.controller, required this.segments});

  final TabController controller;
  final List<_SegmentData> segments;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final anim =
        controller.animation ?? const AlwaysStoppedAnimation<double>(0);
    return Container(
      height: 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: brand.surfaceMuted,
        borderRadius: BorderRadius.circular(14),
      ),
      child: AnimatedBuilder(
        animation: anim,
        builder: (context, _) {
          final n = segments.length;
          final pos = anim.value.clamp(0.0, (n - 1).toDouble());
          final active = pos.round();
          return LayoutBuilder(
            builder: (context, constraints) {
              final segW = constraints.maxWidth / n;
              return Stack(
                children: [
                  // Sliding thumb — positioned by the (possibly fractional)
                  // page offset so it tracks swipes between pages.
                  Positioned(
                    left: segW * pos,
                    top: 0,
                    bottom: 0,
                    width: segW,
                    child: Container(
                      decoration: BoxDecoration(
                        color: brand.surface,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: brand.shadow,
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      for (var i = 0; i < n; i++)
                        Expanded(
                          child: _SegmentButton(
                            data: segments[i],
                            active: i == active,
                            onTap: () => controller.animateTo(i),
                          ),
                        ),
                    ],
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
    required this.data,
    required this.active,
    required this.onTap,
  });

  final _SegmentData data;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration:
                BoxDecoration(color: data.accent, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              data.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.1,
                color: active ? brand.ink : brand.textMuted,
              ),
            ),
          ),
          if (data.count > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: active ? brand.ink : brand.border,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                '${data.count}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: active ? brand.inkInverse : brand.textMuted,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Lightweight per-page empty hint — distinct from the heavier
/// [EmptyStateCard] used when the whole pipeline is empty.
class _PageHint extends StatelessWidget {
  const _PageHint({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 56, 20, 0),
      child: Column(
        children: [
          Icon(icon, size: 30, color: brand.textSoft),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: brand.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.5,
              color: brand.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// A ready application the agent already queued, as a notification row.
/// Shows when it went out and offers a one-tap Undo.
class _SentRow extends StatelessWidget {
  const _SentRow({
    required this.card,
    required this.onUndo,
    this.showDivider = true,
  });

  final PipelineCard card;
  final VoidCallback onUndo;
  final bool showDivider;

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
    return _NotificationRow(
      leadingIcon: Icons.check_circle_rounded,
      leadingColor: brand.success,
      kicker: 'SENT · ${_timeLabel()}',
      title: job.title,
      subtitle: job.company,
      showDivider: showDivider,
      trailing: Material(
        color: brand.surfaceMuted,
        borderRadius: BorderRadius.circular(99),
        child: InkWell(
          onTap: onUndo,
          borderRadius: BorderRadius.circular(99),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: _UndoLabel(),
          ),
        ),
      ),
    );
  }
}

/// The icon + text content of the Undo button, split out so it can be `const`.
class _UndoLabel extends StatelessWidget {
  const _UndoLabel();

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Row(
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
        padding: const EdgeInsets.only(right: 24),
        alignment: Alignment.centerRight,
        color: brand.danger,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: const [
            Icon(Icons.archive_rounded, color: Colors.white, size: 20),
            SizedBox(width: 8),
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

/// A borderless, text-led notification row — the shared visual unit for both
/// pipeline feeds. Leads with a small status icon, then a kicker, title,
/// subtitle and (optionally) the agent's message; a hairline divider closes
/// the row so the feed reads like a notification list, not a stack of cards.
class _NotificationRow extends StatelessWidget {
  const _NotificationRow({
    required this.leadingIcon,
    required this.leadingColor,
    required this.kicker,
    required this.title,
    required this.subtitle,
    this.tag,
    this.tagColor,
    this.message,
    this.trailing,
    this.onTap,
    this.showDivider = true,
  });

  final IconData leadingIcon;
  final Color leadingColor;
  final String kicker;
  final String title;
  final String subtitle;
  final String? tag;
  final Color? tagColor;
  final Widget? message;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: showDivider
              ? BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: brand.border.withValues(alpha: 0.55),
                    ),
                  ),
                )
              : null,
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(leadingIcon, size: 18, color: leadingColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            kicker,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,
                              color: brand.textMuted,
                            ),
                          ),
                        ),
                        if (tag != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            tag!,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.1,
                              color: tagColor ?? brand.textMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: brand.ink,
                        letterSpacing: -0.2,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: brand.textMuted,
                      ),
                    ),
                    if (message != null) ...[
                      const SizedBox(height: 6),
                      message!,
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Borderless icon-only button used as a row's trailing overflow affordance.
/// 44×44 keeps it a comfortable touch target despite the light visual weight.
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
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          excludeFromSemantics: true,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon, size: 20, color: brand.textMuted),
          ),
        ),
      ),
    );
  }
}
