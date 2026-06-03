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

/// The dashboard hero: a vertical timeline of what the agent has actually done
/// for the user, newest work building toward a live "working now" dot while a
/// brief is running.
///
/// Every milestone is derived from durable state (pipeline matches, tailored
/// résumés, learned facts, drafted applications) rather than the ephemeral
/// in-memory activity log — so the story survives an app restart and can never
/// show a fabricated step. The live passive-agent status is layered on top as a
/// pulsing dot only while [PassiveAgentState.isRunning].
class AgentActivityTimeline extends ConsumerWidget {
  const AgentActivityTimeline({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;

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
    final lastBriefAt = ref.watch(
      passiveAgentProvider.select((s) => s.lastBriefAt),
    );
    final liveLabel = ref.watch(
      passiveAgentProvider.select(_liveLabelFor),
    );

    final milestones = <_Milestone>[
      _Milestone(
        icon: Icons.travel_explore_rounded,
        title: role.isEmpty
            ? 'Scanned the market for you'
            : 'Scanned the market for $role roles',
        status: status == AgentBriefStatus.scanning
            ? _DotStatus.active
            : _DotStatus.done,
      ),
      if (matchCount > 0)
        _Milestone(
          icon: Icons.workspace_premium_rounded,
          title: 'Found ${_plural(matchCount, 'strong match', 'strong matches')}',
          subtitle: 'Tap to review your pipeline',
          status: status == AgentBriefStatus.matching
              ? _DotStatus.active
              : _DotStatus.done,
          route: RouteNames.jobs,
        ),
      if (tailoredCount > 0)
        _Milestone(
          icon: Icons.auto_awesome_rounded,
          title: 'Tailored your résumé · '
              '${_plural(tailoredCount, 'version', 'versions')}',
          subtitle: 'Review the changes line by line',
          status: _DotStatus.done,
          route: RouteNames.resumes,
        ),
      if (learnedCount > 0)
        _Milestone(
          icon: Icons.psychology_rounded,
          title: 'Learned ${_plural(learnedCount, 'thing', 'things')} '
              'about your preferences',
          subtitle: 'Saved to your Career Memory',
          status: _DotStatus.done,
          route: RouteNames.profile,
        ),
      if (draftCount > 0)
        _Milestone(
          icon: Icons.drafts_rounded,
          title: '${_plural(draftCount, 'application', 'applications')} '
              'ready to review',
          subtitle: 'Open the tracker to send',
          status: _DotStatus.done,
          route: RouteNames.applications,
        ),
      if (isRunning)
        _Milestone(
          icon: Icons.bolt_rounded,
          title: liveLabel,
          status: _DotStatus.active,
        ),
    ];

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(lastBriefAt: lastBriefAt, isRunning: isRunning),
          const SizedBox(height: 18),
          for (var i = 0; i < milestones.length; i++)
            _TimelineRow(
                  milestone: milestones[i],
                  isFirst: i == 0,
                  isLast: i == milestones.length - 1,
                  lineColor: brand.border,
                )
                .animate(delay: (i * 90).ms)
                .fadeIn(duration: 360.ms)
                .moveY(begin: 10, end: 0, curve: Curves.easeOutCubic),
        ],
      ),
    );
  }
}

/// Compact header: an accent pulse, "Here's what I did", and a relative
/// timestamp so the work reads as something the agent did on its own.
class _Header extends StatelessWidget {
  const _Header({required this.lastBriefAt, required this.isRunning});

  final DateTime? lastBriefAt;
  final bool isRunning;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final stamp = isRunning
        ? 'Working now'
        : lastBriefAt == null
        ? null
        : 'Updated ${_relativeTime(lastBriefAt!)}';
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: brand.accent,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          "Here's what I did",
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
            color: brand.ink,
          ),
        ),
        const Spacer(),
        if (stamp != null)
          Text(
            stamp,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: brand.textMuted,
            ),
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
    required this.lineColor,
  });

  final _Milestone milestone;
  final bool isFirst;
  final bool isLast;
  final Color lineColor;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final tappable = milestone.route != null;

    final content = Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 18),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: brand.surfaceMuted,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Icon(milestone.icon, size: 18, color: brand.ink),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  milestone.title,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                    letterSpacing: -0.2,
                    color: brand.ink,
                  ),
                ),
                if (milestone.subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    milestone.subtitle!,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      height: 1.2,
                      color: brand.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (tappable) ...[
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded, size: 20, color: brand.textMuted),
          ],
        ],
      ),
    );

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Rail(
            status: milestone.status,
            isFirst: isFirst,
            isLast: isLast,
            lineColor: lineColor,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: tappable
                ? InkWell(
                    onTap: () => context.go(milestone.route!),
                    borderRadius: BorderRadius.circular(12),
                    child: content,
                  )
                : content,
          ),
        ],
      ),
    );
  }
}

/// The left "thread": a continuous 2px line with this row's dot punched in
/// near the top, so dots line up with each milestone's icon while the line
/// flows unbroken between them.
class _Rail extends StatelessWidget {
  const _Rail({
    required this.status,
    required this.isFirst,
    required this.isLast,
    required this.lineColor,
  });

  final _DotStatus status;
  final bool isFirst;
  final bool isLast;
  final Color lineColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Top connector — aligns the dot with the icon chip's vertical center.
          Container(
            width: 2,
            height: 13,
            color: isFirst ? Colors.transparent : lineColor,
          ),
          _Dot(status: status),
          Expanded(
            child: Container(
              width: 2,
              color: isLast ? Colors.transparent : lineColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.status});

  final _DotStatus status;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    switch (status) {
      case _DotStatus.done:
        return Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: brand.accent,
            shape: BoxShape.circle,
            border: Border.all(color: brand.bg, width: 2),
          ),
          alignment: Alignment.center,
          child: Icon(Icons.check_rounded, size: 9, color: brand.onAccent),
        );
      case _DotStatus.waiting:
        return Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: brand.bg,
            shape: BoxShape.circle,
            border: Border.all(color: brand.textMuted, width: 2),
          ),
        );
      case _DotStatus.active:
        // A filled dot with a pulsing halo — the agent is doing this now.
        final dot = Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: brand.accent,
            shape: BoxShape.circle,
            border: Border.all(color: brand.bg, width: 2),
          ),
        );
        return SizedBox(
          width: 14,
          height: 14,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: brand.accent.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                  )
                  .animate(
                    onPlay: shouldAnimate(context)
                        ? (c) => c.repeat()
                        : null,
                  )
                  .scaleXY(
                    begin: 1,
                    end: 2.4,
                    duration: 1200.ms,
                    curve: Curves.easeOut,
                  )
                  .fadeOut(duration: 1200.ms),
              dot,
            ],
          ),
        );
    }
  }
}

enum _DotStatus { done, active, waiting }

class _Milestone {
  const _Milestone({
    required this.icon,
    required this.title,
    required this.status,
    this.subtitle,
    this.route,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final _DotStatus status;
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

String _plural(int n, String one, String many) =>
    '$n ${n == 1 ? one : many}';

String _relativeTime(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  if (d.inDays == 1) return 'yesterday';
  return '${d.inDays}d ago';
}
