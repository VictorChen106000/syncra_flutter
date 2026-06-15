import 'dart:async';

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
  return FirestorePaths(
    FirebaseFirestore.instance,
  ).learnedFacts(user.uid).snapshots().map((snap) => snap.docs.length);
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
    final applicationCount = ref.watch(
      applicationsProvider.select((s) => s.items.length),
    );
    final draftCount = ref.watch(
      applicationsProvider.select((s) => s.countOf(ApplicationPhase.draft)),
    );
    final sentCount = ref.watch(
      applicationsProvider.select((s) => s.countOf(ApplicationPhase.sent)),
    );
    final repliedCount = ref.watch(
      applicationsProvider.select((s) => s.countOf(ApplicationPhase.replied)),
    );
    final learnedCount = ref.watch(_learnedFactsCountProvider).value ?? 0;
    final role = (ref.watch(userProfileProvider)?.role ?? '').trim();
    // The agent's onboarding read, carried onto the dashboard so the thought it
    // started during setup finishes here rather than restarting.
    final recommendation =
        (ref.watch(userProfileProvider.select((p) => p?.recommendation)) ?? '')
            .trim();

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
          title:
              'Found ${_plural(matchCount, 'strong match', 'strong matches')}',
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
          title:
              'Learned ${_plural(learnedCount, 'thing', 'things')} about you',
          subtitle: 'Saved to Career Memory',
          time: briefAt,
          route: RouteNames.profile,
        ),
      if (applicationCount > 0)
        _Milestone(
          title: _applicationsTitle(
            total: applicationCount,
            draft: draftCount,
            sent: sentCount,
            replied: repliedCount,
          ),
          subtitle: _applicationsSubtitle(
            draft: draftCount,
            sent: sentCount,
            replied: repliedCount,
          ),
          time: briefAt,
          route: RouteNames.applications,
        ),
      if (isRunning) _Milestone(title: liveLabel, active: true),
    ];

    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // When the agent has a read on the user, it *is* the header — typed
          // out on first load, no card chrome — so the dashboard finishes the
          // thought onboarding started. Otherwise fall back to the plain
          // "Here's what I did" header.
          if (recommendation.isNotEmpty)
            _AgentRead(text: recommendation, isRunning: isRunning)
                .animate()
                .fadeIn(duration: 380.ms)
          else
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

/// The agent's onboarding read, surfaced as the dashboard's *headline* so the
/// thought it started during setup finishes here. No card chrome — it's typed
/// out in the agent's own voice ("you…") on first load, then quietly rolls up
/// to hand the screen back to the activity timeline. The "MY READ ON YOU"
/// eyebrow always stays put with a chevron, so a tap drops the full read back
/// down. Honors reduce-motion by skipping the type-out and the roll, opening
/// collapsed so the timeline is the first thing in view.
class _AgentRead extends StatefulWidget {
  const _AgentRead({required this.text, required this.isRunning});

  final String text;
  final bool isRunning;

  @override
  State<_AgentRead> createState() => _AgentReadState();
}

class _AgentReadState extends State<_AgentRead> {
  bool _expanded = true;
  bool _userToggled = false;
  bool _ready = false;
  Timer? _autoCollapse;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ready) return;
    _ready = true;

    if (!shouldAnimate(context)) {
      // Reduce-motion: no type-out and no roll — open collapsed so the read is
      // a quiet, opt-in disclosure and the timeline leads.
      _expanded = false;
      return;
    }

    // Let the read type out and breathe, then roll it up to reveal the
    // timeline. Mirrors _Typewriter's own duration so the hold starts once the
    // last character lands.
    final typeMs = (widget.text.length * 16).clamp(450, 2000).toInt();
    _autoCollapse = Timer(Duration(milliseconds: typeMs + 1000), () {
      if (mounted && !_userToggled) setState(() => _expanded = false);
    });
  }

  @override
  void dispose() {
    _autoCollapse?.cancel();
    super.dispose();
  }

  void _toggle() {
    _autoCollapse?.cancel();
    setState(() {
      _userToggled = true;
      _expanded = !_expanded;
    });
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final motion = shouldAnimate(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The eyebrow is the persistent anchor and the toggle: tap to roll the
        // read up or back down. Padded out to a comfortable tap target.
        InkWell(
          onTap: _toggle,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Icon(Icons.auto_awesome_rounded, size: 14, color: brand.accent),
                const SizedBox(width: 7),
                Text(
                  'MY READ ON YOU',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                    height: 1,
                    color: brand.textMuted,
                  ),
                ),
                const Spacer(),
                if (widget.isRunning) ...[
                  _PulseDot(color: brand.accent, size: 7),
                  const SizedBox(width: 7),
                  Text(
                    'WORKING NOW',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      height: 1,
                      color: brand.textMuted,
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                AnimatedRotation(
                  // Points down to invite a drop-down; flips up once the read
                  // is showing, matching the "roll up" it triggers.
                  turns: _expanded ? 0.5 : 0.0,
                  duration: motion ? 200.ms : Duration.zero,
                  curve: Curves.easeOut,
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: brand.textMuted.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
        ),
        // The read itself. Kept mounted while collapsed (height rolled to zero,
        // clipped) so the type-out plays exactly once and never replays on a
        // re-expand.
        ClipRect(
          child: AnimatedAlign(
            alignment: Alignment.topCenter,
            heightFactor: _expanded ? 1.0 : 0.0,
            duration: motion ? 340.ms : Duration.zero,
            curve: Curves.easeInOutCubic,
            child: AnimatedOpacity(
              opacity: _expanded ? 1.0 : 0.0,
              duration: motion ? 240.ms : Duration.zero,
              curve: Curves.easeOut,
              child: Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 2),
                child: _Typewriter(
                  text: widget.text,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    height: 1.45,
                    color: brand.ink,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Types [text] out character-by-character once on first build (with a thin
/// trailing caret), then holds the full string. The reveal *is* the entrance,
/// so the agent reads as if it's speaking its mind. Honors reduce-motion by
/// rendering the full text immediately, and never replays on a rebuild because
/// the tween target stays fixed at the text length.
class _Typewriter extends StatelessWidget {
  const _Typewriter({required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    if (!shouldAnimate(context) || text.isEmpty) {
      return Text(text, style: style);
    }
    final ms = (text.length * 16).clamp(450, 2000).toInt();
    return TweenAnimationBuilder<int>(
      tween: IntTween(begin: 0, end: text.length),
      duration: Duration(milliseconds: ms),
      curve: Curves.easeOut,
      builder: (context, shown, _) {
        final done = shown >= text.length;
        return Text(
          done ? text : '${text.substring(0, shown)}▏',
          style: style,
        );
      },
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
        children: [
          _Halo(color: brand.accent, size: size),
          core,
        ],
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

String _applicationsTitle({
  required int total,
  required int draft,
  required int sent,
  required int replied,
}) {
  if (total <= 0) return 'No applications tracked yet';

  final completed = sent + replied;
  if (draft == total) {
    return '${_plural(total, 'application', 'applications')} ready';
  }
  if (completed == total) {
    return '${_plural(total, 'application', 'applications')} sent';
  }
  return '${_plural(total, 'application', 'applications')} tracked';
}

String _applicationsSubtitle({
  required int draft,
  required int sent,
  required int replied,
}) {
  final parts = <String>[
    if (draft > 0) _plural(draft, 'draft', 'drafts'),
    if (sent > 0) _plural(sent, 'sent', 'sent'),
    if (replied > 0) _plural(replied, 'reply', 'replies'),
  ];

  if (parts.isEmpty) return 'Open Application Tracker';
  return '${parts.join(' · ')} · Open tracker';
}

String _relativeTime(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  if (d.inDays == 1) return 'yesterday';
  return '${d.inDays}d ago';
}
