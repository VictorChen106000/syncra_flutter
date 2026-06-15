import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/router/route_names.dart';
import '../../../core/theme/brand_theme.dart';
import '../../../core/utils/motion.dart';
import '../../../data/firestore/pipeline_repository.dart';
import '../../../data/models/job.dart';
import '../../../shared/widgets/app_bottom_nav.dart';
import '../../../shared/widgets/app_header.dart';
import '../../../shared/widgets/app_screen.dart';
import '../../../shared/widgets/gooey_orb.dart';
import '../../agent/state/passive_agent_notifier.dart';
import '../../agent/state/pipeline_autopilot_notifier.dart';
import '../../agent_chat/state/agent_chat_notifier.dart';
import '../state/jobs_notifier.dart';

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
    // When the brief streams in (or adds) pipeline cards, re-run the bounded
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
    final agentHasRun = ref.watch(
      passiveAgentProvider.select((s) => s.lastBriefAt != null),
    );

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
    required this.agentHasRun,
    required this.onDismiss,
  });

  final List<PipelineCard> cards;
  final bool hadAnyPipeline;
  final bool agentHasRun;
  final ValueChanged<Job> onDismiss;

  @override
  ConsumerState<_PipelineFeed> createState() => _PipelineFeedState();
}

class _PipelineFeedState extends ConsumerState<_PipelineFeed> {
  /// Which match-category tab is selected. Orthogonal to the workflow sections
  /// below — this only narrows *which* cards are shown.
  _PipelineFilter _filter = _PipelineFilter.all;

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
    final sent = filtered.where((c) => c.isSent).toList();
    final inProgress = filtered.where((c) => !c.needsYou && !c.isSent).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppHeader.tab(
          title: AppStrings.agentPipeline,
          subtitle: _subtitle(
            cards,
            needs.length + inProgress.length,
            sent.length,
          ),
          // Match-category filter tabs. Only worth showing once there's a
          // pipeline to filter.
          bottom: cards.isEmpty
              ? null
              : _FilterTabs(
                  cards: cards,
                  selected: _filter,
                  onSelected: (f) => setState(() => _filter = f),
                ),
        ),
        Expanded(
          child: cards.isEmpty
              ? _GooeyEmptyState(
                  agentHasRun: widget.agentHasRun,
                  hadAnyPipeline: widget.hadAnyPipeline,
                )
              : filtered.isEmpty
              ? _EmptyFilter(filter: _filter)
              : _list(context, ref, needs, inProgress, sent),
        ),
      ],
    );
  }

  String? _subtitle(List<PipelineCard> cards, int active, int sent) {
    if (cards.isEmpty) return 'Your pipeline is quiet';

    final parts = <String>[];

    if (active > 0) {
      parts.add(active == 1 ? '1 in progress' : '$active in progress');
    }

    if (sent > 0) {
      parts.add(sent == 1 ? '1 handled' : '$sent handled');
    }

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
    // Only the section that needs you wears the lime accent — "working" fades
    // into a soft grey, "handled" settles to plain ink. Colour means "look
    // here", not "this is a list".

    List<Widget> section(String label, Color accent, List<PipelineCard> items) {
      if (items.isEmpty) return const [];
      return [
        _SectionHeader(label: label, count: items.length, accent: accent),
        for (var i = 0; i < items.length; i++)
          Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _SwipeDismissible(
                  key: ValueKey('pipe-${items[i].id}'),
                  onDismissed: () => widget.onDismiss(items[i].job),
                  child: _PipelineCard(
                    card: items[i],
                    onTap: () {
                      ref
                          .read(agentChatProvider.notifier)
                          .openJobThread(items[i].job);
                      context.go(RouteNames.agentChat);
                    },
                  ),
                ),
              )
              .animate(delay: (animIndex++ * 55).ms)
              .fadeIn(duration: 320.ms)
              .moveY(begin: 14, end: 0, curve: Curves.easeOutCubic),
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
        ...section('Needs approval', brand.accent, needs),
        ...section('Syncra working', brand.textSoft, inProgress),
        ...section('Handled', brand.ink, sent),
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
    _PipelineFilter.allMatch => 'Strong',
    _PipelineFilter.severalMatch => 'Partial',
    _PipelineFilter.noMatch => 'Stretch',
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
// Pipeline card — a standalone job listing card: a company mark, the role,
// salary, a row of tag pills, then the agentic footer (stage stepper + the one
// status line). It floats on a soft category-tinted shadow so the feed reads as
// a premium stack of cards rather than a flat list.
// ---------------------------------------------------------------------------

class _PipelineCard extends StatelessWidget {
  const _PipelineCard({required this.card, required this.onTap});

  final PipelineCard card;
  final VoidCallback onTap;

  /// The single status line under the stepper. Action-led for cards that need
  /// you, quiet and factual for the rest. The dots carry stage, so this never
  /// repeats it.
  String _phrase() {
    if (card.trustRiskLevel == 'high') {
      return 'High-risk signals found';
    }
    if (card.trustRiskLevel == 'medium') {
      return 'Needs trust verification';
    }

    if (card.isSent) {
      return card.stage == PipelineStage.replied
          ? 'Reply received'
          : 'Handled ${_timeAgo(card.createdAt)}';
    }
    if (card.stage == PipelineStage.drafted) return 'Draft ready for review';
    if (card.job.missingSkills.isNotEmpty) {
      return 'Missing ${card.job.missingSkills.take(2).join(', ')}';
    }
    if (card.needsYou) {
      return card.job.category == JobCategory.inputNeeded
          ? 'Needs your input'
          : 'Needs your approval';
    }
    return switch (card.stage) {
      PipelineStage.tailored => 'Tailored resume ready',
      _ => 'Syncra queued this role',
    };
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final job = card.job;
    // Cards that need you or need trust review weight their status line in ink.
    final actionable = card.needsYou || card.needsTrustReview;
    // A strong match is the one positive signal worth the lime accent; the rest
    // of the card stays monochrome.
    final isStrong = job.category == JobCategory.ready;
    // The single status line is the only place an alert can shout: high-risk
    // postings turn red, real actions weight to ink, everything else is muted.
    final phraseColor = card.trustRiskLevel == 'high'
        ? brand.danger
        : actionable
        ? brand.ink
        : brand.textMuted;

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
              // Two pills at most: match quality leads (lime when strong); a
              // trust pill appears only when the role needs verification — a
              // clean card is itself the "looks safe" signal.
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  // Only show the match tier once the AI has actually scored
                  // the role; an unmatched role carries no real fit signal.
                  if (job.matched)
                    _Tag(label: _matchLabel(job.category), solid: isStrong),
                  if (card.needsTrustReview)
                    _TrustGuardTag(
                      card: card,
                      onTap: () => _showTrustGuardDetails(context, card),
                    ),
                ],
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
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Company line under the logo: "Company · Location", or just the company when
/// no location is known. Keeps location out of the pill row.
String _companyLine(Job job) {
  final location = job.location.trim();
  if (location.isEmpty) return job.company;
  return '${job.company}  ·  $location';
}

/// Short, human match label for the lead pill. Mirrors the filter-tab wording
/// (Strong / Partial / Stretch) — never "No match", which reads as a mistake
/// for a role the agent chose to pipeline.
String _matchLabel(JobCategory category) => switch (category) {
  JobCategory.ready => 'Strong match',
  JobCategory.inputNeeded => 'Partial match',
  JobCategory.exploration => 'Stretch',
};

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

String _trustRiskLabel(PipelineCard card) {
  final label = card.trustRiskLabel.trim().isEmpty
      ? 'Not checked'
      : card.trustRiskLabel.trim();

  if (card.trustSignalsCount <= 0) return 'Trust: $label';
  return 'Trust: $label · ${card.trustSignalsCount}';
}

String _trustSafeNextStep(PipelineCard card) {
  final saved = card.trustSafeNextStep.trim();
  if (saved.isNotEmpty) return saved;

  return switch (card.trustRiskLevel) {
    'high' =>
      'Do not send personal documents or payment. Verify the company and posting first.',
    'medium' =>
      'Verify the company site, recruiter identity, and application link before outreach.',
    _ =>
      'No obvious red flags found. Still verify the official posting before applying.',
  };
}

Color _signalSeverityColor(String severity, BrandTheme brand) {
  return switch (severity) {
    'high' => brand.danger,
    'medium' => brand.warning,
    _ => brand.textSoft,
  };
}

String _signalSeverityLabel(String severity) {
  return switch (severity) {
    'high' => 'High',
    'medium' => 'Medium',
    _ => 'Note',
  };
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

void _showTrustGuardDetails(BuildContext context, PipelineCard card) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => _TrustGuardDetailsSheet(card: card),
  );
}

class _TrustGuardDetailsSheet extends StatelessWidget {
  const _TrustGuardDetailsSheet({required this.card});

  final PipelineCard card;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final color = _trustRiskColor(card.trustRiskLevel, brand);
    final icon = _trustRiskIcon(card.trustRiskLevel);
    final signals = card.trustSignals;
    final safeNextStep = _trustSafeNextStep(card);

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 12, 12, 16),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: brand.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: brand.border),
          boxShadow: [
            BoxShadow(
              color: brand.shadow.withValues(alpha: 0.22),
              blurRadius: 28,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: brand.isDark ? 0.2 : 0.12),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: color.withValues(alpha: 0.34)),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, size: 19, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Trust Guard · ${card.trustRiskLabel}',
                    style: TextStyle(
                      color: brand.ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Quick red-flag screen only. This does not certify the job as legitimate.',
              style: TextStyle(
                color: brand.textMuted,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 16),
            if (signals.isEmpty)
              _TrustGuardEmptySignals(color: color)
            else
              for (final signal in signals) ...[
                _TrustSignalRow(signal: signal),
                const SizedBox(height: 9),
              ],
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: brand.surfaceMuted,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: brand.border.withValues(alpha: 0.7)),
              ),
              child: Text(
                safeNextStep,
                style: TextStyle(
                  color: brand.ink,
                  fontSize: 12.8,
                  fontWeight: FontWeight.w700,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrustGuardEmptySignals extends StatelessWidget {
  const _TrustGuardEmptySignals({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: color.withValues(alpha: brand.isDark ? 0.16 : 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline_rounded, size: 17, color: color),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              'No obvious red flags were found in the saved posting text.',
              style: TextStyle(
                color: brand.ink,
                fontSize: 12.8,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrustSignalRow extends StatelessWidget {
  const _TrustSignalRow({required this.signal});

  final Map<String, String> signal;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final severity = signal['severity'] ?? 'medium';
    final color = _signalSeverityColor(severity, brand);
    final label = signal['label'] ?? 'Trust signal';
    final detail = signal['detail'] ?? '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: brand.surfaceMuted,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: brand.border.withValues(alpha: 0.7)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, size: 17, color: color),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_signalSeverityLabel(severity)} · $label',
                  style: TextStyle(
                    color: brand.ink,
                    fontSize: 12.8,
                    fontWeight: FontWeight.w900,
                    height: 1.25,
                  ),
                ),
                if (detail.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    detail,
                    style: TextStyle(
                      color: brand.textMuted,
                      fontSize: 12.3,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TrustGuardTag extends StatelessWidget {
  const _TrustGuardTag({required this.card, required this.onTap});

  final PipelineCard card;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final level = card.trustRiskLevel;
    final color = _trustRiskColor(level, brand);
    final icon = _trustRiskIcon(level);
    final label = _trustRiskLabel(card);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppConstants.pillRadius),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: brand.isDark ? 0.18 : 0.12),
            borderRadius: BorderRadius.circular(AppConstants.pillRadius),
            border: Border.all(color: color.withValues(alpha: 0.34)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12.5, color: color),
              const SizedBox(width: 5),
              Text(
                label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.45,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
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
      title = 'Your pipeline is empty';
      body =
          'Enable "Today\'s brief" in Settings, then run it from the '
          'dashboard. Syncra will line up new roles here.';
      actionLabel = 'Open dashboard';
      route = RouteNames.dashboard;
    } else if (!hadAnyPipeline) {
      title = 'No roles queued right now';
      body =
          'Syncra scanned but found no strong matches. Broaden your '
          'criteria, or ask the agent to explore a new direction.';
      actionLabel = 'Ask the agent';
      route = RouteNames.agentChat;
    } else {
      title = 'All caught up';
      body =
          'Every role Syncra surfaced has been handled. The next brief '
          'will refill your pipeline.';
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
