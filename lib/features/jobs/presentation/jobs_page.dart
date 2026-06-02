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
import '../../../shared/widgets/gooey_orb.dart';
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
      child: _PipelineFeed(
        cards: visible,
        // There were cards once but they've all been dismissed → distinguishes
        // "all caught up" from "the agent found nothing".
        hadAnyPipeline: state.pendingCards.isNotEmpty,
        agentHasRun: agentHasRun,
        onDismiss: _dismiss,
        onMore: (job) => JobActionSheet.show(context, job),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pipeline feed — one vertical scroll, grouped into three priority sections.
//
//   • Needs you    — anything waiting on the user (missing info, or a finished
//                    draft to review & send), regardless of stage.
//   • In progress  — the agent is working or has it queued; nothing for you yet.
//   • Sent         — terminal; already out the door (+ awaiting reply).
//
// Each card carries a [_StageStepper] so you can watch a job crawl from
// Matched → Tailored → Drafted → Sent. Stage is the per-card progress axis;
// the sections are the orthogonal "does this need me?" axis. No segmented
// control — the whole pipeline state reads at a glance.
// ---------------------------------------------------------------------------

class _PipelineFeed extends ConsumerWidget {
  const _PipelineFeed({
    required this.cards,
    required this.hadAnyPipeline,
    required this.agentHasRun,
    required this.onDismiss,
    required this.onMore,
  });

  final List<PipelineCard> cards;
  final bool hadAnyPipeline;
  final bool agentHasRun;
  final ValueChanged<Job> onDismiss;
  final ValueChanged<Job> onMore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final needs = cards.where((c) => c.needsYou).toList()
      // Drafts ready to send float above missing-info matches — they're the
      // most actionable thing on the page.
      ..sort((a, b) {
        final byStage = _needsRank(a).compareTo(_needsRank(b));
        return byStage != 0 ? byStage : b.createdAt.compareTo(a.createdAt);
      });
    final sent = cards.where((c) => c.isSent).toList();
    final inProgress =
        cards.where((c) => !c.needsYou && !c.isSent).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppHeader.tab(
          title: AppStrings.agentPipeline,
          subtitle: _subtitle(needs.length + inProgress.length, sent.length),
        ),
        Expanded(
          child: cards.isEmpty
              ? _GooeyEmptyState(
                  agentHasRun: agentHasRun,
                  hadAnyPipeline: hadAnyPipeline,
                )
              : _list(context, ref, needs, inProgress, sent),
        ),
      ],
    );
  }

  String? _subtitle(int active, int sent) {
    if (cards.isEmpty) return 'Quiet — no agent activity yet';
    final parts = <String>[
      if (active > 0) '$active active',
      if (sent > 0) '$sent sent',
    ];
    return parts.isEmpty ? 'All caught up' : parts.join(' · ');
  }

  Widget _list(
    BuildContext context,
    WidgetRef ref,
    List<PipelineCard> needs,
    List<PipelineCard> inProgress,
    List<PipelineCard> sent,
  ) {
    final brand = context.brand;
    var animIndex = 0;

    List<Widget> section(
      String label,
      Color accent,
      List<PipelineCard> items,
    ) {
      if (items.isEmpty) return const [];
      return [
        _SectionHeader(label: label, count: items.length, accent: accent),
        for (var i = 0; i < items.length; i++)
          _SwipeDismissible(
            key: ValueKey('pipe-${items[i].id}'),
            onDismissed: () => onDismiss(items[i].job),
            child: _PipelineRow(
              card: items[i],
              showDivider: i < items.length - 1,
              onMore: () => onMore(items[i].job),
              onTap: () {
                ref.read(agentChatProvider.notifier).openJobThread(items[i].job);
                context.go(RouteNames.agentChat);
              },
            ),
          )
              .animate(delay: (animIndex++ * 55).ms)
              .fadeIn(duration: 320.ms)
              .moveY(begin: 12, end: 0, curve: Curves.easeOutCubic),
      ];
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.screenHorizontalPadding,
        4,
        AppConstants.screenHorizontalPadding,
        140,
      ),
      children: [
        ...section('Needs you', brand.warning, needs),
        ...section('In progress', brand.ink, inProgress),
        ...section('Sent', brand.success, sent),
      ],
    );
  }
}

/// Sort key inside "Needs you": drafts awaiting send (0) before missing-info
/// matches (1). Lower sorts first.
int _needsRank(PipelineCard c) =>
    c.stage == PipelineStage.drafted ? 0 : 1;

/// Compact relative time for the "Sent" kicker, e.g. "just now", "12m ago".
String _timeAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  return '${d.inDays}d ago';
}

// ---------------------------------------------------------------------------
// Section header — uppercase kicker + count chip. Mirrors the row kicker's
// typographic weight so the feed reads as one consistent system.
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.label,
    required this.count,
    required this.accent,
  });

  final String label;
  final int count;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 2),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.3,
              color: brand.textMuted,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.2,
              color: brand.textSoft,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pipeline row — the shared borderless notification row, with a stage stepper
// (and, when relevant, the agent's note) tucked under the subtitle.
// ---------------------------------------------------------------------------

class _PipelineRow extends StatelessWidget {
  const _PipelineRow({
    required this.card,
    required this.onTap,
    required this.onMore,
    this.showDivider = true,
  });

  final PipelineCard card;
  final VoidCallback onTap;
  final VoidCallback onMore;
  final bool showDivider;

  /// The single status line under the stepper. Action-led for cards that need
  /// you, quiet and factual for the rest. The dots carry stage, so this never
  /// repeats it.
  String _phrase() {
    if (card.isSent) {
      return card.stage == PipelineStage.replied
          ? 'Replied'
          : 'Sent ${_timeAgo(card.createdAt)}';
    }
    if (card.stage == PipelineStage.drafted) return 'Review & send';
    if (card.job.missingSkills.isNotEmpty) {
      return 'Missing ${card.job.missingSkills.take(2).join(', ')}';
    }
    if (card.needsYou) {
      return card.job.category == JobCategory.inputNeeded
          ? 'Needs input'
          : 'Worth a look';
    }
    return switch (card.stage) {
      PipelineStage.tailored => 'Resume tailored',
      _ => 'Queued',
    };
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final job = card.job;
    // Cards that need you weight their status line in ink; the rest stay muted.
    final actionable = card.needsYou;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: showDivider
              ? BoxDecoration(
                  border: Border(
                    bottom:
                        BorderSide(color: brand.border.withValues(alpha: 0.5)),
                  ),
                )
              : null,
          padding: const EdgeInsets.symmetric(vertical: 15),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: job.title,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: brand.ink,
                              letterSpacing: -0.2,
                            ),
                          ),
                          TextSpan(
                            text: '   ${job.company}',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: brand.textMuted,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 9),
                    Row(
                      children: [
                        _StageStepper(stage: card.stage),
                        const SizedBox(width: 11),
                        Flexible(
                          child: Text(
                            _phrase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.1,
                              color: actionable ? brand.ink : brand.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (!card.isSent)
                _IconActionButton(
                  icon: Icons.more_horiz_rounded,
                  semanticLabel: 'More actions',
                  onTap: onMore,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Stage stepper — four dots (Matched · Tailored · Drafted · Sent) with the
// current stage spelled out. Done dots are inked, the current one glows in the
// brand accent, future ones are hollow. This is the bit that makes the page
// read as *progression* rather than a flat list.
// ---------------------------------------------------------------------------

class _StageStepper extends StatelessWidget {
  const _StageStepper({required this.stage});

  final PipelineStage stage;

  // Matched · Tailored · Drafted · Sent. No label drawn here — the row's status
  // line carries the words, so the stepper stays pure progress.
  int get _activeIndex => switch (stage) {
        PipelineStage.matched => 0,
        PipelineStage.tailored => 1,
        PipelineStage.drafted => 2,
        PipelineStage.sent => 3,
        PipelineStage.replied => 3,
      };

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final active = _activeIndex;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 4; i++) ...[
          _Dot(done: i < active, current: i == active, brand: brand),
          if (i < 3) _Connector(filled: i < active, brand: brand),
        ],
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.done, required this.current, required this.brand});

  final bool done;
  final bool current;
  final BrandTheme brand;

  @override
  Widget build(BuildContext context) {
    final color = current
        ? brand.accentBright
        : done
            ? brand.ink
            : brand.border;
    final size = current ? 7.0 : 6.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _Connector extends StatelessWidget {
  const _Connector({required this.filled, required this.brand});

  final bool filled;
  final BrandTheme brand;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 13,
      height: 1.5,
      margin: const EdgeInsets.symmetric(horizontal: 2.5),
      decoration: BoxDecoration(
        color: filled ? brand.ink.withValues(alpha: 0.4) : brand.border,
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state — the gooey orb plus a flavor of copy that explains *why* it's
// empty and gives one way forward.
// ---------------------------------------------------------------------------

class _GooeyEmptyState extends StatelessWidget {
  const _GooeyEmptyState({
    required this.agentHasRun,
    required this.hadAnyPipeline,
  });

  final bool agentHasRun;
  final bool hadAnyPipeline;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;

    final String title;
    final String body;
    final String actionLabel;
    final String route;

    if (!agentHasRun) {
      title = 'Your agent is idle';
      body = 'Enable "Today\'s brief" in Settings, then run it from the '
          'dashboard. New roles land here as the agent finds them.';
      actionLabel = 'Open dashboard';
      route = RouteNames.dashboard;
    } else if (!hadAnyPipeline) {
      title = 'No new roles right now';
      body = 'The agent scanned but found no strong matches. Broaden your '
          'criteria, or ask the agent to explore a new direction.';
      actionLabel = 'Ask the agent';
      route = RouteNames.agentChat;
    } else {
      title = 'You\'re all caught up';
      body = 'Every role the agent surfaced has been handled. The next '
          'brief will refill your pipeline.';
      actionLabel = 'Back to dashboard';
      route = RouteNames.dashboard;
    }

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(36, 0, 36, 120),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const GooeyOrb(size: 140)
                .animate()
                .fadeIn(duration: 500.ms)
                .scale(
                  begin: const Offset(0.8, 0.8),
                  end: const Offset(1, 1),
                  curve: Curves.easeOutCubic,
                ),
            const SizedBox(height: 28),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: brand.ink,
                letterSpacing: -0.4,
                height: 1.2,
              ),
            )
                .animate(delay: 120.ms)
                .fadeIn(duration: 420.ms)
                .moveY(begin: 8, end: 0, curve: Curves.easeOutCubic),
            const SizedBox(height: 10),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: brand.textMuted,
                height: 1.5,
                letterSpacing: -0.1,
              ),
            ).animate(delay: 220.ms).fadeIn(duration: 420.ms),
            const SizedBox(height: 24),
            _PillButton(
              label: actionLabel,
              onTap: () => context.go(route),
            ).animate(delay: 320.ms).fadeIn(duration: 420.ms),
          ],
        ),
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Material(
      color: brand.surfaceMuted,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.1,
              color: brand.ink,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared row primitives — kept from the original page.
// ---------------------------------------------------------------------------

/// Wraps a child in a swipe-left-to-dismiss gesture. Reveals a red archive
/// background as the user drags.
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
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
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
