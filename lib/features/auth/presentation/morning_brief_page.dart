import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/router/route_names.dart';
import '../../../core/theme/brand_theme.dart';
import '../../../data/models/job.dart';
import '../../agent/state/passive_agent_notifier.dart';
import '../models/app_user.dart';
import '../state/auth_notifier.dart';

// Slightly off-white "ink" used across this page. Pure #FFFFFF on the brand's
// pure-black background was reading as harsh / fatiguing — backing off ~6%
// keeps the dark aesthetic without strobing the eye.
const Color _softInk = Color(0xFFF1F1F3);

/// The morning briefing the agent delivers right after sign-in.
///
/// Intentionally dark in both themes — uses [BrandTheme.dark] hardcoded so
/// the headline aesthetic doesn't shift when system flips to light.
class MorningBriefPage extends ConsumerStatefulWidget {
  const MorningBriefPage({super.key, this.userName});

  final String? userName;

  @override
  ConsumerState<MorningBriefPage> createState() => _MorningBriefPageState();
}

class _MorningBriefPageState extends ConsumerState<MorningBriefPage> {
  static const _brand = BrandTheme.dark;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = ref.read(passiveAgentProvider);
      if (!state.hasPipeline && !state.isRunning) {
        ref.read(passiveAgentProvider.notifier).runBrief();
      }
    });
  }

  void _continue() {
    ref.read(passiveAgentProvider.notifier).markMorningBriefShown();
    context.go(RouteNames.dashboard);
  }

  String _firstName(String? raw, AppUser? user) {
    final source = (raw?.isNotEmpty ?? false)
        ? raw!
        : (user?.displayName ?? 'there');
    return source.split(' ').first;
  }

  @override
  Widget build(BuildContext context) {
    final agent = ref.watch(passiveAgentProvider);
    final auth = ref.watch(authProvider);
    final firstName = _firstName(widget.userName, auth.appUser);
    return Scaffold(
      backgroundColor: _brand.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _continue,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'Skip',
                    style: TextStyle(
                      color: _softInk.withValues(alpha: 0.62),
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      letterSpacing: 0.1,
                    ),
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '${AppStrings.goodMorning}\n$firstName.',
                style: GoogleFonts.inter(
                  color: _softInk,
                  fontSize: 42,
                  fontWeight: FontWeight.w900,
                  height: 1.08,
                  letterSpacing: -1.1,
                ),
              )
                  .animate()
                  .fadeIn(duration: 500.ms)
                  .moveY(begin: 12, end: 0, curve: Curves.easeOutCubic),
              const SizedBox(height: 28),
              _BriefBody(agent: agent),
              const Spacer(),
              _BriefStatusLine(agent: agent),
              const SizedBox(height: 16),
              _ContinueButton(onTap: _continue, ready: agent.hasPipeline)
                  .animate(delay: 400.ms)
                  .fadeIn(duration: 360.ms)
                  .moveY(begin: 10, end: 0, curve: Curves.easeOutCubic),
            ],
          ),
        ),
      ),
    );
  }
}

class _BriefBody extends StatelessWidget {
  const _BriefBody({required this.agent});

  final PassiveAgentState agent;

  @override
  Widget build(BuildContext context) {
    if (agent.status == AgentBriefStatus.error) {
      return _ErrorBody(message: agent.lastError ?? 'Brief failed.');
    }
    if (agent.isRunning || !agent.hasPipeline) {
      return _RunningBody(agent: agent);
    }
    final job = agent.topMatch;
    if (job == null) {
      return _RunningBody(agent: agent);
    }
    return _MatchBody(job: job);
  }
}

class _RunningBody extends StatelessWidget {
  const _RunningBody({required this.agent});

  final PassiveAgentState agent;

  String get _line {
    switch (agent.status) {
      case AgentBriefStatus.scanning:
        return 'Scanning fresh roles…';
      case AgentBriefStatus.matching:
        return 'Scoring each role against your profile…';
      case AgentBriefStatus.done:
        return 'Wrapping up your brief…';
      case AgentBriefStatus.error:
        return 'Brief failed.';
      case AgentBriefStatus.idle:
        return 'Warming up…';
    }
  }

  @override
  Widget build(BuildContext context) {
    const brand = BrandTheme.dark;
    return Row(
      children: [
        SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2.2,
            color: brand.accent,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            _line,
            style: TextStyle(
              color: _softInk.withValues(alpha: 0.72),
              fontSize: 14.5,
              fontWeight: FontWeight.w500,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}

class _MatchBody extends StatelessWidget {
  const _MatchBody({required this.job});

  final Job job;

  @override
  Widget build(BuildContext context) {
    const brand = BrandTheme.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'TOP MATCH',
          style: TextStyle(
            color: _softInk.withValues(alpha: 0.48),
            fontSize: 10.5,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.6,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${job.matchScore}',
              style: GoogleFonts.inter(
                color: brand.accent,
                fontSize: 92,
                fontWeight: FontWeight.w900,
                height: 0.95,
                letterSpacing: -3.2,
              ),
            )
                .animate(delay: 200.ms)
                .scale(
                  begin: const Offset(0.92, 0.92),
                  end: const Offset(1, 1),
                  curve: Curves.easeOutCubic,
                  duration: 600.ms,
                )
                .fadeIn(),
            Padding(
              padding: const EdgeInsets.only(left: 6, bottom: 16),
              child: Text(
                '%',
                style: TextStyle(
                  color: brand.accent.withValues(alpha: 0.70),
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          '${job.title} · ${job.company}',
          style: TextStyle(
            color: _softInk,
            fontSize: 17,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
            height: 1.35,
          ),
        ).animate(delay: 320.ms).fadeIn().moveY(begin: 6, end: 0),
        const SizedBox(height: 10),
        Text(
          job.agentJustification.isNotEmpty
              ? job.agentJustification
              : '${job.title} at ${job.company} looks like a strong fit.',
          style: TextStyle(
            color: _softInk.withValues(alpha: 0.68),
            fontSize: 15,
            height: 1.6,
            fontWeight: FontWeight.w500,
            letterSpacing: -0.05,
          ),
        ).animate(delay: 420.ms).fadeIn(),
      ],
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    const brand = BrandTheme.dark;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.error_outline_rounded,
          color: brand.danger,
          size: 18,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Brief failed',
                style: TextStyle(
                  color: _softInk,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                message,
                style: TextStyle(
                  color: _softInk.withValues(alpha: 0.65),
                  fontSize: 13.5,
                  height: 1.55,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BriefStatusLine extends StatelessWidget {
  const _BriefStatusLine({required this.agent});

  final PassiveAgentState agent;

  @override
  Widget build(BuildContext context) {
    final text = !agent.hasPipeline
        ? (agent.isRunning ? 'Brief in progress…' : 'No matches yet')
        : '${agent.readyCount} ready · ${agent.inputNeededCount} need input · ${agent.explorationCount} strategic';
    return Text(
      text,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: _softInk.withValues(alpha: 0.58),
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        height: 1.5,
      ),
    );
  }
}

class _ContinueButton extends StatelessWidget {
  const _ContinueButton({required this.onTap, required this.ready});

  final VoidCallback onTap;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    const brand = BrandTheme.dark;
    // Icon-only round button anchored to the right edge — the headline and
    // brief body already carry the verbal context; this is just the action.
    return Align(
      alignment: Alignment.centerRight,
      child: Semantics(
        button: true,
        label: ready ? 'Continue' : 'Skip for now',
        child: Material(
          color: ready ? brand.accent : brand.surface,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: ready ? null : Border.all(color: brand.border),
              ),
              child: Icon(
                Icons.arrow_forward_rounded,
                color: ready ? brand.onAccent : _softInk,
                size: 26,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
