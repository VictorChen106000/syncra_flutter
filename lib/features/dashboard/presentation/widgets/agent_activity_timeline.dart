import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/theme/brand_theme.dart';
import '../../../../core/utils/motion.dart';
import '../../../../data/firestore/firestore_paths.dart';
import '../../../../data/models/tracked_application.dart';
import '../../../agent/state/passive_agent_notifier.dart';
import '../../../applications/state/applications_notifier.dart';
import '../../../auth/state/auth_notifier.dart';
import '../../../auth/state/user_profile_notifier.dart';
import '../../../jobs/state/jobs_notifier.dart';
import '../../../resumes/state/resume_notifier.dart';

/// Count of facts the agent has learned about the user (Career Memory). Backed
/// by the same `learned_facts` collection the Profile page reads, so the
/// dashboard's "Learned N things" milestone always matches what Profile shows.
/// Returns 0 for guests / signed-out (no per-user collection to read).
final _learnedFactsCountProvider = StreamProvider.autoDispose<int>((ref) {
  final user = ref.watch(authProvider.select((s) => s.appUser));
  if (user == null || user.isGuest) return Stream.value(0);
  return FirestorePaths(FirebaseFirestore.instance)
      .learnedFacts(user.uid)
      .snapshots()
      .map((snap) => snap.docs.length);
});

/// The dashboard hero: a quiet vertical timeline of what the agent has actually
/// done, completed work resolving into a single live dot while a brief runs.
///
/// Premium-minimal by intent: no per-row glyphs, monochrome ink dots, and a
/// lone lime accent reserved for the "working now" point so the eye lands on
/// what's live. Every milestone is derived from durable state (pipeline
/// matches, tailored résumés, learned facts, drafted applications) rather than
/// the ephemeral in-memory log — so the story survives a restart and can never
/// show a fabricated step. The live passive-agent status is layered on top.
class AgentActivityTimeline extends ConsumerWidget {
  const AgentActivityTimeline({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matchCount = ref.watch(jobsProvider.select((s) => s.cards.length));
    final tailoredCount = ref.watch(
      resumeProvider.select((s) => s.tailoredResumes.length),
    );
    final draftCount = ref.watch(
      applicationsProvider.select((s) => s.countOf(ApplicationPhase.draft)),
    );
    final learnedCount = ref.watch(_learnedFactsCountProvider).value ?? 0;
    final role = (ref.watch(userProfileProvider)?.role ?? '').trim();

    final status = ref.watch(passiveAgentProvider.select((s) => s.status));
    final isRunning = ref.watch(
      passiveAgentProvider.select((s) => s.isRunning),
    );
    final briefAt = ref.watch(
      passiveAgentProvider.select((s) => s.lastBriefAt),
    );
    final liveLabel = ref.watch(passiveAgentProvider.select(_liveLabelFor));

    final milestones = <_Milestone>[
      _Milestone(
        title: role.isEmpty
            ? 'Scanned the market for you'
            : 'Scanned the market for $role roles',
        time: briefAt,
        active: status == AgentBriefStatus.scanning,
      ),
      if (matchCount > 0)
        _Milestone(
          title: 'Found ${_plural(matchCount, 'strong match', 'strong matches')}',
          subtitle: 'Review your pipeline',
          time: briefAt,
          active: status == AgentBriefStatus.matching,
          route: RouteNames.jobs,
        ),
      if (tailoredCount > 0)
        _Milestone(
          title: 'Tailored your résumé',
          subtitle: _plural(tailoredCount, 'version ready', 'versions ready'),
          time: briefAt,
          route: RouteNames.resumes,
        ),
      if (learnedCount > 0)
        _Milestone(
          title: 'Learned ${_plural(learnedCount, 'thing', 'things')} about you',
          subtitle: 'Saved to Career Memory',
          time: briefAt,
          route: RouteNames.profile,
        ),
      if (draftCount > 0)
        _Milestone(
          title: '${_plural(draftCount, 'application', 'applications')} ready',
          subtitle: 'Open the tracker to send',
          time: briefAt,
          route: RouteNames.applications,
        ),
      if (isRunning)
        _Milestone(title: liveLabel, active: true),
    ];

    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(isRunning: isRunning, briefAt: briefAt),
          const SizedBox(height: 24),
          for (var i = 0; i < milestones.length; i++)
            _TimelineRow(
                  milestone: milestones[i],
                  isFirst: i == 0,
                  isLast: i == milestones.length - 1,
                )
                .animate(delay: (i * 80).ms)
                .fadeIn(duration: 420.ms)
                .moveY(begin: 12, end: 0, curve: Curves.easeOutCubic),
        ],
      ),
    );
  }
}

/// Quiet header: a title and, only while a brief runs, a "Working now"
/// indicator. Per-step times live on the rows, so the header stays bare.
class _Header extends StatelessWidget {
  const _Header({required this.isRunning, required this.briefAt});

  final bool isRunning;
  final DateTime? briefAt;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          "Here's what I did",
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
            height: 1.1,
            color: brand.ink,
          ),
        ),
        const Spacer(),
        if (isRunning)
          Row(
            children: [
              _PulseDot(color: brand.accent, size: 7),
              const SizedBox(width: 7),
              Text(
                'WORKING NOW',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: brand.textMuted,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.milestone,
    required this.isFirst,
    required this.isLast,
  });

  final _Milestone milestone;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final m = milestone;
    final tappable = m.route != null;
    final eyebrow = m.active
        ? 'NOW'
        : (m.time != null ? _relativeTime(m.time!).toUpperCase() : null);

    final content = Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (eyebrow != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Text(
                eyebrow,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                  height: 1,
                  color: m.active ? brand.ink : brand.textMuted,
                ),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: Text(
                  m.title,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                    height: 1.25,
                    color: brand.ink,
                  ),
                ),
              ),
              if (tappable) ...[
                const SizedBox(width: 10),
                Icon(
                  Icons.arrow_outward_rounded,
                  size: 17,
                  color: brand.textMuted.withValues(alpha: 0.7),
                ),
              ],
            ],
          ),
          if (m.subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              m.subtitle!,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.1,
                height: 1.3,
                color: brand.textMuted,
              ),
            ),
          ],
        ],
      ),
    );

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Rail(active: m.active, isFirst: isFirst, isLast: isLast),
          const SizedBox(width: 16),
          Expanded(
            child: tappable
                ? InkWell(
                    onTap: () => context.go(m.route!),
                    borderRadius: BorderRadius.circular(14),
                    child: content,
                  )
                : content,
          ),
        ],
      ),
    );
  }
}

/// The left "thread": a hairline connector with this row's dot. The dot sits
/// near the top so it lands on the time eyebrow / title; the line flows
/// unbroken to the next milestone.
class _Rail extends StatelessWidget {
  const _Rail({
    required this.active,
    required this.isFirst,
    required this.isLast,
  });

  final bool active;
  final bool isFirst;
  final bool isLast;

  static const double _dot = 18;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final line = brand.border;
    return SizedBox(
      width: _dot,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Aligns the dot's centre with the first text line.
          Container(
            width: 1.5,
            height: 4,
            color: isFirst ? Colors.transparent : line,
          ),
          _Dot(active: active, size: _dot),
          Expanded(
            child: Container(
              width: 1.5,
              color: isLast ? Colors.transparent : line,
            ),
          ),
        ],
      ),
    );
  }
}

/// A pure geometric marker — no glyph. Completed steps are a solid ink dot;
/// the step in progress is a faded-green dot ringed in green with a breathing
/// halo, so "done" settles to black and only the live step carries colour.
class _Dot extends StatelessWidget {
  const _Dot({required this.active, required this.size});

  final bool active;
  final double size;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    // A ring in the page background separates the dot from the connector line.
    final core = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: active ? brand.accent.withValues(alpha: 0.32) : brand.ink,
        shape: BoxShape.circle,
        border: Border.all(
          color: active ? brand.accent : brand.bg,
          width: active ? 2 : 3,
        ),
      ),
    );
    if (!active) return core;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [_Halo(color: brand.accent, size: size), core],
      ),
    );
  }
}

/// Small solid dot with a breathing halo — used for the header's "working
/// now" indicator.
class _PulseDot extends StatelessWidget {
  const _PulseDot({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          _Halo(color: color, size: size),
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ],
      ),
    );
  }
}

/// The lone piece of motion in the timeline: a ring that scales out and fades
/// on a loop. Gated on reduce-motion, where it renders nothing.
class _Halo extends StatelessWidget {
  const _Halo({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (!shouldAnimate(context)) return const SizedBox.shrink();
    return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.45),
            shape: BoxShape.circle,
          ),
        )
        .animate(onPlay: (c) => c.repeat())
        .scaleXY(begin: 1, end: 2.6, duration: 1400.ms, curve: Curves.easeOut)
        .fadeOut(duration: 1400.ms);
  }
}

class _Milestone {
  const _Milestone({
    required this.title,
    this.subtitle,
    this.time,
    this.active = false,
    this.route,
  });

  final String title;
  final String? subtitle;

  /// When this work happened — rendered as the time eyebrow. Null hides it.
  final DateTime? time;

  /// The step the agent is on right now: drives the "NOW" eyebrow and the lime
  /// pulsing dot.
  final bool active;
  final String? route;
}

/// Live one-liner for the in-progress dot, preferring the agent's own last
/// message over a generic stage label.
String _liveLabelFor(PassiveAgentState s) {
  final msg = s.lastMessage?.trim();
  if (msg != null && msg.isNotEmpty) {
    return msg.length > 80 ? '${msg.substring(0, 80)}…' : msg;
  }
  return switch (s.status) {
    AgentBriefStatus.scanning => 'Scanning roles…',
    AgentBriefStatus.matching => 'Matching against your résumé…',
    _ => 'Working…',
  };
}

String _plural(int n, String one, String many) => '$n ${n == 1 ? one : many}';

String _relativeTime(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  if (d.inDays == 1) return 'yesterday';
  return '${d.inDays}d ago';
}
