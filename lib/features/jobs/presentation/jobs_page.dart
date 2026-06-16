import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/router/route_names.dart';
import '../../../core/theme/brand_theme.dart';
import '../../../core/utils/motion.dart';
import '../../../core/utils/url_opener.dart';
import '../../../data/firestore/pipeline_repository.dart';
import '../../../data/models/job.dart';
import '../../../data/models/tracked_application.dart';
import '../../../shared/widgets/app_bottom_nav.dart';
import '../../../shared/widgets/app_header.dart';
import '../../../shared/widgets/app_screen.dart';
import '../../../shared/widgets/gooey_orb.dart';
import '../../agent/state/pipeline_autopilot_notifier.dart';
import '../../agent_chat/state/agent_chat_notifier.dart';
import '../../applications/state/applications_notifier.dart';
import '../state/jobs_notifier.dart';
import 'widgets/job_links_sheet.dart';

class JobsPage extends ConsumerStatefulWidget {
  const JobsPage({super.key});

  @override
  ConsumerState<JobsPage> createState() => _JobsPageState();
}

class _JobsPageState extends ConsumerState<JobsPage> {
  @override
  void initState() {
    super.initState();
    // Kick the auto-processor once the first frame is up. It no-ops on Assist,
    // without an API key, or when there are no fresh strong/low-risk matches —
    // and is idempotent, so the re-trigger below is safe too.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(pipelineAutopilotProvider.notifier).processNow();
    });
  }

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
    // When the agent saves new pipeline cards, re-run the bounded
    // auto-processor. Idempotent — already-handled jobs are skipped.
    ref.listen(jobsProvider.select((s) => s.cards.length), (prev, next) {
      if (next > (prev ?? 0)) {
        ref.read(pipelineAutopilotProvider.notifier).processNow();
      }
    });

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
      child: _PipelineFeed(
        cards: visible,
        // There were cards once but they've all been dismissed → distinguishes
        // "all caught up" from "the agent hasn't found anything yet".
        hadAnyPipeline: state.pendingCards.isNotEmpty,
        onDismiss: _dismiss,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pipeline feed — one vertical scroll, grouped into three priority
// sections.
//
//  • Needs approval — anything waiting on the user: missing info, review, or
//                     a finished draft to approve.
//  • Syncra working — the agent is preparing the next step; nothing for you yet.
//  • Handled        — terminal; already sent, handled, or awaiting reply.
//
// Each card carries a [_StageStepper] so you can watch a job crawl from
// Matched → Tailored → Drafted → Sent. Stage is the per-card progress axis;
// the sections are the orthogonal "does this need me?" axis. No segmented
// control — the whole pipeline state reads at a glance.
// ---------------------------------------------------------------------------

class _PipelineFeed extends ConsumerStatefulWidget {
  const _PipelineFeed({
    required this.cards,
    required this.hadAnyPipeline,
    required this.onDismiss,
  });

  final List<PipelineCard> cards;
  final bool hadAnyPipeline;
  final ValueChanged<Job> onDismiss;

  @override
  ConsumerState<_PipelineFeed> createState() => _PipelineFeedState();
}

class _PipelineFeedState extends ConsumerState<_PipelineFeed> {
  /// Which match-category tab is selected (live board only).
  _PipelineFilter _filter = _PipelineFilter.all;

  /// Header mode: live Pipeline vs. the finished-work History. Null until the
  /// user picks — then we open on History only when the board is empty but a
  /// record exists, so a returning user never lands on a blank page.
  bool? _showHistoryOverride;

  @override
  Widget build(BuildContext context) {
    final cards = widget.cards;
    final filtered = cards
        .where((c) => _filter.matches(c))
        .toList(growable: false);

    final needs = filtered.where((c) => c.needsYou).toList()
      // Drafts ready to send float above missing-info matches — they're the
      // most actionable thing on the page.
      ..sort((a, b) {
        final byStage = _needsRank(a).compareTo(_needsRank(b));
        return byStage != 0 ? byStage : b.createdAt.compareTo(a.createdAt);
      });
    final inProgress = filtered.where((c) => !c.needsYou && !c.isSent).toList();

    // Split the off-board application record into the two slices the title
    // toggle shows. The line is the one irreversible act — you hit send:
    //   • draft (never sent) → still "needs you", so it belongs on the board
    //   • sent / replied     → the History record
    // Deduped against anything still live on the board.
    final liveJobIds = {for (final c in cards) c.job.id};
    final offBoard = ref
        .watch(applicationsProvider.select((s) => s.items))
        .where((a) => !liveJobIds.contains(a.job.id));
    final draftApps =
        offBoard.where((a) => a.phase == ApplicationPhase.draft).toList()
          ..sort((a, b) => b.sortAt.compareTo(a.sortAt));
    final historyApps =
        offBoard.where((a) => a.phase != ApplicationPhase.draft).toList()
          ..sort((a, b) => b.sortAt.compareTo(a.sortAt));

    // Everything still in motion: live cards + unsent drafts. Filter-independent
    // so the header count stays honest.
    final activeCount = cards.length + draftApps.length;
    final showHistory =
        _showHistoryOverride ?? (activeCount == 0 && historyApps.isNotEmpty);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppHeader.tab(
          // The big title *is* the switch — tap the dimmed word to flip views.
          titleWidget: _SwitchTitle(
            showHistory: showHistory,
            subtitle: showHistory
                ? _historySubtitle(historyApps.length)
                : _activeSubtitle(activeCount),
            onChanged: (h) => setState(() => _showHistoryOverride = h),
          ),
          // Match filters narrow the live board only — hidden in History and
          // when there's no board to filter.
          bottom: showHistory || cards.isEmpty
              ? null
              : _FilterTabs(
                  cards: cards,
                  selected: _filter,
                  onSelected: (f) => setState(() => _filter = f),
                ),
        ),
        Expanded(
          child: showHistory
              ? _historyView(context, ref, historyApps)
              : _pipelineView(
                  context,
                  ref,
                  cards,
                  filtered,
                  needs,
                  inProgress,
                  draftApps,
                ),
        ),
      ],
    );
  }

  String? _activeSubtitle(int active) {
    if (active == 0) return 'Your pipeline is quiet';
    return active == 1 ? '1 in progress' : '$active in progress';
  }

  String? _historySubtitle(int count) {
    if (count == 0) return 'Nothing sent yet';
    return count == 1 ? '1 sent' : '$count sent';
  }

  /// The live board — needs-you and in-progress sections. "Needs you" also
  /// carries unsent drafts (apps with no live card): you drafted them but never
  /// hit send, so they're still your move. Sent work has moved to History.
  Widget _pipelineView(
    BuildContext context,
    WidgetRef ref,
    List<PipelineCard> cards,
    List<PipelineCard> filtered,
    List<PipelineCard> needs,
    List<PipelineCard> inProgress,
    List<TrackedApplication> draftApps,
  ) {
    if (cards.isEmpty && draftApps.isEmpty) {
      return _GooeyEmptyState(hadAnyPipeline: widget.hadAnyPipeline);
    }
    if (filtered.isEmpty && draftApps.isEmpty) {
      return _EmptyFilter(filter: _filter);
    }

    final brand = context.brand;
    var animIndex = 0;

    void goToThread(Job job, {PipelineStage stage = PipelineStage.matched}) {
      // Is the background autopilot already on this job? If so the opener shows
      // "preparing…" instead of a duplicate "Prepare draft".
      final claimed = ref
          .read(pipelineAutopilotProvider.notifier)
          .isAutopilotHandling(job.id);
      ref
          .read(agentChatProvider.notifier)
          .openJobThread(job, stage: stage, autopilotClaimed: claimed);
      context.go(RouteNames.agentChat);
    }

    // A live pipeline card: swipe-dismissible, taps into the agent thread.
    Widget liveEntry(PipelineCard card) =>
        Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _SwipeDismissible(
                key: ValueKey('pipe-${card.id}'),
                onDismissed: () => widget.onDismiss(card.job),
                child: _PipelineCard(
                  card: card,
                  onTap: () => goToThread(card.job, stage: card.stage),
                ),
              ),
            )
            .animate(delay: (animIndex++ * 55).ms)
            .fadeIn(duration: 320.ms)
            .moveY(begin: 14, end: 0, curve: Curves.easeOutCubic);

    // An unsent draft (application with no live card): the same card, not
    // dismissible (it's a record); long-press opens its detail/notes.
    Widget draftEntry(TrackedApplication app) =>
        Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _PipelineCard(
                card: _cardFromApplication(app),
                onTap: () => goToThread(app.job, stage: PipelineStage.drafted),
                application: app,
              ),
            )
            .animate(delay: (animIndex++ * 55).ms)
            .fadeIn(duration: 320.ms)
            .moveY(begin: 14, end: 0, curve: Curves.easeOutCubic);

    final children = <Widget>[];

    // Needs you = unsent drafts (most actionable, lead) + live needs-you cards.
    final needsTotal = draftApps.length + needs.length;
    if (needsTotal > 0) {
      children.add(
        _SectionHeader(
          label: 'Needs approval',
          count: needsTotal,
          accent: brand.accent,
        ),
      );
      for (final app in draftApps) {
        children.add(draftEntry(app));
      }
      for (final card in needs) {
        children.add(liveEntry(card));
      }
    }

    if (inProgress.isNotEmpty) {
      children.add(
        _SectionHeader(
          label: 'Syncra working',
          count: inProgress.length,
          accent: brand.textSoft,
        ),
      );
      for (final card in inProgress) {
        children.add(liveEntry(card));
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.screenHorizontalPadding,
        4,
        AppConstants.screenHorizontalPadding,
        140,
      ),
      children: children,
    );
  }

  /// History — the same job cards as the board, mapped to *finished* pipeline
  /// cards so the stepper reads as a completed timeline. Primary tap is the
  /// agent handoff (identical to a live card); long-press opens the record
  /// (notes / follow-up / mark replied).
  Widget _historyView(
    BuildContext context,
    WidgetRef ref,
    List<TrackedApplication> history,
  ) {
    if (history.isEmpty) return const _HistoryEmpty();

    var animIndex = 0;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.screenHorizontalPadding,
        8,
        AppConstants.screenHorizontalPadding,
        140,
      ),
      children: [
        for (final app in history)
          Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _PipelineCard(
                  card: _cardFromApplication(app),
                  onTap: () {
                    ref
                        .read(agentChatProvider.notifier)
                        .openJobThread(app.job, stage: PipelineStage.sent);
                    context.go(RouteNames.agentChat);
                  },
                  application: app,
                ),
              )
              .animate(delay: (animIndex++ * 45).ms)
              .fadeIn(duration: 300.ms)
              .moveY(begin: 12, end: 0, curve: Curves.easeOutCubic),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Match-category filter — the header tabs (All / All match / Several match /
// No match). Maps 1:1 onto [JobCategory]; "All" is the no-op pass-through.
// ---------------------------------------------------------------------------

enum _PipelineFilter { all, allMatch, severalMatch, noMatch }

extension _PipelineFilterX on _PipelineFilter {
  String get label => switch (this) {
    _PipelineFilter.all => 'All',
    _PipelineFilter.allMatch => 'All Match',
    _PipelineFilter.severalMatch => 'Several Match',
    _PipelineFilter.noMatch => 'No Match',
  };

  /// True when [card] belongs under this tab. "All" admits everything.
  bool matches(PipelineCard card) => switch (this) {
    _PipelineFilter.all => true,
    _PipelineFilter.allMatch => card.job.category == JobCategory.ready,
    _PipelineFilter.severalMatch =>
      card.job.category == JobCategory.inputNeeded,
    _PipelineFilter.noMatch => card.job.category == JobCategory.exploration,
  };
}

/// The horizontal row of filter pills under the page title. Each pill carries a
/// live count so the user can see at a glance how the pipeline splits.
class _FilterTabs extends StatelessWidget {
  const _FilterTabs({
    required this.cards,
    required this.selected,
    required this.onSelected,
  });

  final List<PipelineCard> cards;
  final _PipelineFilter selected;
  final ValueChanged<_PipelineFilter> onSelected;

  int _countFor(_PipelineFilter f) => cards.where((c) => f.matches(c)).length;

  @override
  Widget build(BuildContext context) {
    // Fade the right edge so a clipped pill reads as "scroll for more" rather
    // than a layout bug. dstIn keeps the pills' own colors and just tapers
    // their alpha over the last slice of the viewport.
    return ShaderMask(
      shaderCallback: (rect) => const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        stops: [0.0, 0.88, 1.0],
        colors: [Colors.black, Colors.black, Colors.transparent],
      ).createShader(rect),
      blendMode: BlendMode.dstIn,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: [
            for (final f in _PipelineFilter.values) ...[
              _FilterChip(
                label: f.label,
                count: _countFor(f),
                selected: f == selected,
                onTap: () => onSelected(f),
              ),
              if (f != _PipelineFilter.values.last) const SizedBox(width: 8),
            ],
            // Trailing slack so the last pill can scroll clear of the fade.
            const SizedBox(width: 28),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final fg = selected ? brand.onAccent : brand.ink;
    return Material(
      color: selected ? brand.accent : brand.surface,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: selected ? brand.accent : brand.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.1,
                  color: fg,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: selected
                      ? brand.onAccent.withValues(alpha: 0.7)
                      : brand.textSoft,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown when a filter is active but no card falls under it — distinct from the
/// page-wide gooey empty state (which means "no pipeline at all").
class _EmptyFilter extends StatelessWidget {
  const _EmptyFilter({required this.filter});

  final _PipelineFilter filter;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(36, 0, 36, 120),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.filter_list_off_rounded,
              size: 34,
              color: brand.textSoft,
            ),
            const SizedBox(height: 14),
            Text(
              'No "${filter.label}" roles right now',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: brand.ink,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Try another tab to see the rest of your pipeline.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: brand.textMuted,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sort key inside "Needs you": drafts awaiting send (0) before missing-info
/// matches (1). Lower sorts first.
int _needsRank(PipelineCard c) => c.stage == PipelineStage.drafted ? 0 : 1;

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
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: accent,
              shape: BoxShape.circle,
              // A soft halo only on the lime "needs you" marker; the quieter
              // sections get a crisp dot with no glow.
              boxShadow: accent == brand.accent
                  ? [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.35),
                        blurRadius: 7,
                        spreadRadius: 0.5,
                      ),
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 9),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.35,
              color: brand.ink,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: accent.withValues(alpha: 0.34)),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.2,
                color: brand.ink,
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pipeline ⇄ History — one feed, two slices of the same job cards. The header
// title doubles as the switch (_SwitchTitle); History reuses the live card via
// _cardFromApplication so a finished role reads as the same card with a
// completed stepper.
// ---------------------------------------------------------------------------

/// Maps a finished [TrackedApplication] onto a [PipelineCard] so History reuses
/// the exact same card. Status is [approved] (it's left the live board) and the
/// stage carries the phase, so the stepper renders a completed timeline.
PipelineCard _cardFromApplication(TrackedApplication app) {
  final stage = switch (app.phase) {
    ApplicationPhase.draft => PipelineStage.drafted,
    ApplicationPhase.sent => PipelineStage.sent,
    ApplicationPhase.replied => PipelineStage.replied,
  };
  return PipelineCard(
    id: app.id,
    job: app.job,
    status: PipelineCardStatus.approved,
    createdAt: app.sortAt,
    stage: stage,
  );
}

/// The big title *is* the mode switch: two large words, the active one inked,
/// the other dimmed but still visible (so History never hides). Tap the dim one
/// to flip the feed. Counts ride in the subtitle.
class _SwitchTitle extends StatelessWidget {
  const _SwitchTitle({
    required this.showHistory,
    required this.subtitle,
    required this.onChanged,
  });

  final bool showHistory;
  final String? subtitle;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _TitleWord(
                label: 'Pipeline',
                active: !showHistory,
                onTap: () => onChanged(false),
              ),
              const SizedBox(width: 16),
              _TitleWord(
                label: 'History',
                active: showHistory,
                onTap: () => onChanged(true),
              ),
            ],
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          Text(
            subtitle!,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: brand.textMuted,
              height: 1.45,
            ),
          ),
        ],
      ],
    );
  }
}

class _TitleWord extends StatelessWidget {
  const _TitleWord({
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
    return Semantics(
      button: true,
      selected: active,
      label: label,
      child: GestureDetector(
        onTap: active ? null : onTap,
        behavior: HitTestBehavior.opaque,
        // Plain Text on purpose: the row scales inside a FittedBox, and an
        // implicitly-animated style (AnimatedDefaultTextStyle) mis-rasterises
        // to solid blocks when scaled. The active/dimmed colour swaps instantly.
        child: Text(
          label,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.6,
            height: 1,
            color: active ? brand.ink : brand.ink.withValues(alpha: 0.22),
          ),
        ),
      ),
    );
  }
}

/// Empty History — finished roles flow here automatically. Mirrors the quiet,
/// centred tone of the other empty states.
class _HistoryEmpty extends StatelessWidget {
  const _HistoryEmpty();

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(36, 0, 36, 120),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle_outline_rounded,
              size: 34,
              color: brand.textSoft,
            ),
            const SizedBox(height: 14),
            Text(
              'Nothing sent yet',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: brand.ink,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Roles you send land here automatically — the same card, '
              'with its timeline completed.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: brand.textMuted,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pipeline card — a standalone job listing card: a company mark, the role,
// salary, a row of tag pills, then the agentic footer (stage stepper + the one
// status line). It floats on a soft category-tinted shadow so the feed reads as
// a premium stack of cards rather than a flat list.
// ---------------------------------------------------------------------------

class _PipelineCard extends StatelessWidget {
  const _PipelineCard({
    required this.card,
    required this.onTap,
    this.application,
  });

  final PipelineCard card;
  final VoidCallback onTap;

  /// The backing application for app-backed cards (History + unsent drafts).
  /// When set, the footer shows the link/resume/email action icons that open the
  /// application-link modal ([JobLinksSheet]); live pipeline cards leave it null
  /// and keep just the agent handoff on tap.
  final TrackedApplication? application;

  /// The single status line under the stepper. Action-led for cards that need
  /// you, quiet and factual for the rest. The dots carry stage, so this never
  /// repeats it.
  String _phrase() {
    if (card.isSent) {
      return card.stage == PipelineStage.replied
          ? 'Reply received'
          : 'Handled ${_timeAgo(card.createdAt)}';
    }
    // Application-link-first: when a real apply/source link exists the visible
    // win leads with it, so the user always has an "Open application" outcome
    // even before any email is drafted. Falls back to the prior copy otherwise.
    final hasLink = _hasOpenableLink(card.job);
    if (card.stage == PipelineStage.drafted) {
      return hasLink
          ? 'Application link ready · Draft ready'
          : 'Draft ready for review';
    }
    if (card.job.missingSkills.isNotEmpty) {
      return 'Missing ${card.job.missingSkills.take(2).join(', ')}';
    }
    if (card.needsYou) {
      return card.job.category == JobCategory.inputNeeded
          ? 'Needs your input'
          : 'Needs your approval';
    }
    return switch (card.stage) {
      PipelineStage.tailored =>
        hasLink
            ? 'Application link · Resume tailored'
            : 'Tailored resume ready',
      _ => hasLink ? 'Application link ready' : 'Syncra queued this role',
    };
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final job = card.job;
    // Cards that need you weight their status line in ink.
    final actionable = card.needsYou;
    // A strong match is the one positive signal worth the lime accent; the rest
    // of the card stays monochrome.
    final isStrong = job.category == JobCategory.ready;
    // The single status line weights to ink for real actions, muted otherwise.
    final phraseColor = actionable ? brand.ink : brand.textMuted;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        child: Container(
          decoration: BoxDecoration(
            color: brand.surface,
            borderRadius: BorderRadius.circular(AppConstants.cardRadius),
            border: Border.all(color: brand.border.withValues(alpha: 0.6)),
            boxShadow: [
              // One neutral shadow so the card lifts on any backdrop — no
              // coloured glow.
              BoxShadow(
                color: brand.shadow,
                blurRadius: 18,
                spreadRadius: -2,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Company mark + "company · location", with a quiet relative time.
              Row(
                children: [
                  _LogoMark(company: job.company),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      _companyLine(job),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: brand.textMuted,
                        letterSpacing: -0.1,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _timeAgo(card.createdAt),
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: brand.textSoft,
                      letterSpacing: -0.1,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 11),
              // Role + salary — the headline the eye lands on first.
              Text(
                job.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: brand.ink,
                  letterSpacing: -0.35,
                  height: 1.15,
                ),
              ),
              if (job.salary.trim().isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  job.salary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: brand.textMuted,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              // The match-quality pill (lime when strong) — shown only once the
              // AI has actually scored the role; an unmatched role carries no
              // real fit signal.
              if (job.matched)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [_Tag(label: job.matchLabel, solid: isStrong)],
                ),
              const SizedBox(height: 13),
              // Agentic footer — the progress stepper plus the single status
              // line, which doubles as the application's verdict.
              Row(
                children: [
                  _StageStepper(stage: card.stage),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      _phrase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.1,
                        color: phraseColor,
                      ),
                    ),
                  ),
                  if (application != null) ...[
                    const SizedBox(width: 8),
                    _JobActionIcons(job: job, application: application!),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The three compact action icons on app-backed cards (link · resume · email),
/// lower-right. Each opens the application-link modal ([JobLinksSheet]); the
/// icon's tint signals availability — active in ink, muted when that channel has
/// nothing yet (no link, no tailored resume, no sent outreach).
class _JobActionIcons extends StatelessWidget {
  const _JobActionIcons({required this.job, required this.application});

  final Job job;
  final TrackedApplication application;

  @override
  Widget build(BuildContext context) {
    final linkActive = _hasOpenableLink(job);
    final resumeActive = application.resumeId != null;
    final emailActive = application.sentEmailId != null;

    void open() => JobLinksSheet.show(context, job, application: application);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _MiniIconButton(
          icon: Icons.link_rounded,
          active: linkActive,
          onTap: open,
        ),
        _MiniIconButton(
          icon: Icons.description_outlined,
          active: resumeActive,
          onTap: open,
        ),
        _MiniIconButton(
          icon: Icons.mail_outline_rounded,
          active: emailActive,
          onTap: open,
        ),
      ],
    );
  }
}

class _MiniIconButton extends StatelessWidget {
  const _MiniIconButton({
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(
            icon,
            size: 17,
            color: active ? brand.ink : brand.textSoft,
          ),
        ),
      ),
    );
  }
}

/// True when [job] carries any apply/source/company link we'd be willing to
/// open — drives the application-link-first status copy and the link icon's
/// active tint.
bool _hasOpenableLink(Job job) =>
    UrlOpener.canOpen(job.applyLink) ||
    UrlOpener.canOpen(job.sourceUrl) ||
    UrlOpener.canOpen(job.googleJobLink) ||
    UrlOpener.canOpen(job.employerWebsite);

/// Company line under the logo: "Company · Location", or just the company when
/// no location is known. Keeps location out of the pill row.
String _companyLine(Job job) {
  final location = job.location.trim();
  if (location.isEmpty) return job.company;
  return '${job.company}  ·  $location';
}

/// A company "logo" stand-in — the first initial on a lime tile with a black
/// glyph: the brand's signature mark. A slow sheen sweeps across it so the feed
/// feels alive without leaning on per-company rainbow colours.
class _LogoMark extends StatelessWidget {
  const _LogoMark({required this.company});

  final String company;

  String get _initial {
    final trimmed = company.trim();
    return trimmed.isEmpty ? '?' : trimmed.substring(0, 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: brand.accent,
            borderRadius: BorderRadius.circular(13),
            boxShadow: [
              BoxShadow(
                color: brand.accent.withValues(alpha: 0.3),
                blurRadius: 12,
                spreadRadius: -3,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Text(
            _initial,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: brand.onAccent,
              letterSpacing: -0.5,
            ),
          ),
        )
        .animate(onPlay: repeatIfMotion(context))
        .shimmer(
          duration: 2200.ms,
          color: Colors.white.withValues(alpha: 0.55),
          angle: 0.4,
        );
  }
}

/// A pill tag — the match label or a skill. A solid lime chip for a strong
/// match (the one positive signal worth colour); a quiet neutral chip otherwise.
class _Tag extends StatelessWidget {
  const _Tag({required this.label, this.solid = false});

  final String label;
  final bool solid;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: solid ? brand.accent : brand.surfaceMuted,
        borderRadius: BorderRadius.circular(AppConstants.pillRadius),
        border: solid
            ? null
            : Border.all(color: brand.border.withValues(alpha: 0.7)),
      ),
      child: Text(
        label.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
          color: solid ? brand.onAccent : brand.textMuted,
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
    // The current stage reads as a glowing, oversized dot so progress is
    // legible at a glance; done dots are solid ink, future dots hollow-faint.
    final size = current
        ? 10.0
        : done
        ? 6.0
        : 5.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: current
            ? [
                BoxShadow(
                  color: brand.accentBright.withValues(alpha: 0.4),
                  blurRadius: 6,
                  spreadRadius: 0.5,
                ),
              ]
            : null,
      ),
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
  const _GooeyEmptyState({required this.hadAnyPipeline});

  final bool hadAnyPipeline;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;

    final String title;
    final String body;
    final String actionLabel;
    final String route;

    if (!hadAnyPipeline) {
      title = 'Your pipeline is empty';
      body =
          'Ask Syncra to find roles for you — it will search, match them to '
          'your résumé, and line up the strongest ones here.';
      actionLabel = 'Ask Syncra';
      route = RouteNames.agentChat;
    } else {
      title = 'All caught up';
      body =
          'Every role Syncra surfaced has been handled. Ask Syncra to find '
          'more roles whenever you want to refill your pipeline.';
      actionLabel = 'Ask Syncra';
      route = RouteNames.agentChat;
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
