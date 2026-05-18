import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/utils/motion.dart';
import '../../../core/router/route_names.dart';
import '../../../data/models/job.dart';
import '../../agent/state/passive_agent_notifier.dart';
import '../models/app_user.dart';
import '../state/auth_notifier.dart';

/// The morning briefing the agent delivers right after sign-in.
///
/// Auto-triggers a passive-agent brief on entry, then narrates the best
/// match Claude found. Falls back to the seeded "Binance 94%" headline
/// when the brief is still running or running in mock mode.
class MorningBriefPage extends ConsumerStatefulWidget {
  const MorningBriefPage({super.key, this.userName});

  final String? userName;

  @override
  ConsumerState<MorningBriefPage> createState() => _MorningBriefPageState();
}

class _MorningBriefPageState extends ConsumerState<MorningBriefPage> {
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
      backgroundColor: AppColors.ink,
      body: Stack(
        children: [
          Positioned(
            top: MediaQuery.sizeOf(context).height * 0.18,
            right: -100,
            child:
                Container(
                      width: 360,
                      height: 360,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.accent.withValues(alpha: 0.20),
                      ),
                    )
                    .animate(onPlay: repeatIfMotion(context, reverse: true))
                    .scale(
                      duration: 4.seconds,
                      begin: const Offset(1, 1),
                      end: const Offset(1.15, 1.15),
                      curve: Curves.easeInOut,
                    )
                    .fadeIn(duration: 1.seconds),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _LiveBadge(isLive: agent.isLiveModeEnabled),
                      const Spacer(),
                      TextButton(
                        onPressed: _continue,
                        child: Text(
                          'Skip',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.70),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                        '${AppStrings.goodMorning}\n$firstName.',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 40,
                          fontWeight: FontWeight.w900,
                          height: 1.1,
                          letterSpacing: -1.4,
                        ),
                      )
                      .animate()
                      .fadeIn(duration: 600.ms)
                      .moveY(begin: 14, end: 0),
                  const SizedBox(height: 28),
                  _BriefBody(agent: agent),
                  const Spacer(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(child: _BriefStatusLine(agent: agent)),
                      const SizedBox(width: 12),
                      _NextButton(onTap: _continue)
                          .animate(delay: 700.ms)
                          .scale(
                            begin: const Offset(0.8, 0.8),
                            end: const Offset(1, 1),
                            curve: Curves.easeOutBack,
                          )
                          .fadeIn(),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge({required this.isLive});

  final bool isLive;

  @override
  Widget build(BuildContext context) {
    final label = isLive ? 'CLAUDE HAIKU · LIVE' : 'DEMO MODE';
    final color = isLive
        ? AppColors.accent
        : Colors.white.withValues(alpha: 0.40);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 10,
              letterSpacing: 1.4,
            ),
          ),
        ],
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
        return 'Asking Claude to score each role…';
      case AgentBriefStatus.done:
        return 'Wrapping up your brief…';
      case AgentBriefStatus.error:
        return 'Brief failed.';
      case AgentBriefStatus.idle:
        return 'Warming up your brief…';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Row(
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _line,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14.5,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          agent.isLiveModeEnabled
              ? 'Claude Haiku is checking each role against your resume.'
              : 'Running in demo mode. Set ANTHROPIC_API_KEY to call Claude live.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.55),
            fontSize: 13,
            height: 1.4,
            fontWeight: FontWeight.w500,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: TextSpan(
            style: const TextStyle(
              fontSize: 20,
              height: 1.45,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
            children: [
              TextSpan(
                text: '${job.company} ',
                style: const TextStyle(
                  color: AppColors.accent,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const TextSpan(text: 'matched your profile.'),
            ],
          ),
        ).animate(delay: 200.ms).fadeIn().moveY(begin: 8, end: 0),
        const SizedBox(height: 12),
        Text(
              '${job.matchScore}%',
              style: const TextStyle(
                color: AppColors.accent,
                fontSize: 72,
                fontWeight: FontWeight.w900,
                height: 1.05,
                letterSpacing: -3,
              ),
            )
            .animate(delay: 350.ms)
            .scale(
              begin: const Offset(0.9, 0.9),
              end: const Offset(1, 1),
              curve: Curves.easeOutBack,
              duration: 700.ms,
            )
            .fadeIn(),
        const SizedBox(height: 8),
        Container(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Text(
            job.agentJustification.isNotEmpty
                ? job.agentJustification
                : '${job.title} at ${job.company} looks like a strong fit.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.70),
              fontSize: 16,
              height: 1.45,
              fontWeight: FontWeight.w500,
            ),
          ),
        ).animate(delay: 500.ms).fadeIn(),
      ],
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.50)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'Brief failed',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.95),
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: 13,
              height: 1.45,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _BriefStatusLine extends StatelessWidget {
  const _BriefStatusLine({required this.agent});

  final PassiveAgentState agent;

  @override
  Widget build(BuildContext context) {
    if (!agent.hasPipeline) {
      return Text(
        agent.isRunning ? 'Brief in progress…' : 'Tap → to skip',
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.55),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      );
    }
    return Text(
      '${agent.readyCount} ready · ${agent.inputNeededCount} need input · ${agent.explorationCount} strategic',
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.80),
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _NextButton extends StatelessWidget {
  const _NextButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.accent,
      shape: const CircleBorder(),
      elevation: 6,
      shadowColor: AppColors.accent.withValues(alpha: 0.40),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const SizedBox(
          width: 64,
          height: 64,
          child: Icon(
            Icons.chevron_right_rounded,
            color: AppColors.ink,
            size: 32,
          ),
        ),
      ),
    );
  }
}
