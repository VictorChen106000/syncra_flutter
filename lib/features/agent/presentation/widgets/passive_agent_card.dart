import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/brand_theme.dart';
import '../../../../core/utils/motion.dart';
import '../../state/passive_agent_notifier.dart';

class PassiveAgentCard extends ConsumerWidget {
  const PassiveAgentCard({super.key});

  String _statusLabel(AgentBriefStatus s) {
    switch (s) {
      case AgentBriefStatus.idle:
        return 'Standing by';
      case AgentBriefStatus.scanning:
        return 'Scanning job boards…';
      case AgentBriefStatus.matching:
        return 'Scoring matches…';
      case AgentBriefStatus.done:
        return 'Brief ready';
      case AgentBriefStatus.error:
        return 'Brief failed';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final state = ref.watch(passiveAgentProvider);
    final notifier = ref.read(passiveAgentProvider.notifier);
    final running = state.isRunning;
    final lastBrief = state.lastBriefAt;
    return Container(
      padding: const EdgeInsets.all(AppConstants.cardPadding),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(AppConstants.largeCardRadius),
        border: Border.all(color: brand.border),
        boxShadow: [
          BoxShadow(
            color: brand.shadow,
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _StatusOrb(running: running),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PASSIVE AGENT',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.4,
                        color: brand.textMuted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _statusLabel(state.status),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: brand.ink,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
              ),
              _BriefButton(
                running: running,
                onPressed: notifier.runBrief,
              ),
            ],
          ),
          const SizedBox(height: 14),
          _PipelineBreakdown(
            ready: state.readyCount,
            inputNeeded: state.inputNeededCount,
            exploration: state.explorationCount,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  lastBrief == null
                      ? 'Tap "Run brief" to scan overnight matches.'
                      : 'Last brief at ${DateFormat('h:mm a').format(lastBrief)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: brand.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => context.go(RouteNames.jobs),
                style: TextButton.styleFrom(
                  foregroundColor: brand.ink,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Open pipeline',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(width: 4),
                    Icon(Icons.arrow_forward_rounded, size: 14),
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

class _StatusOrb extends StatelessWidget {
  const _StatusOrb({required this.running});

  final bool running;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final core = Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: brand.ink,
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Icon(
        running ? Icons.radar_rounded : Icons.bolt_rounded,
        color: brand.accent,
        size: 18,
      ),
    );
    if (!running) return core;
    return core
        .animate(onPlay: repeatIfMotion(context, reverse: true))
        .scale(
          duration: 900.ms,
          begin: const Offset(1, 1),
          end: const Offset(1.06, 1.06),
          curve: Curves.easeInOut,
        );
  }
}

class _BriefButton extends StatelessWidget {
  const _BriefButton({required this.running, required this.onPressed});

  final bool running;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: running ? brand.surfaceMuted : brand.ink,
        foregroundColor: running ? brand.ink : brand.inkInverse,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      onPressed: running ? null : onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (running)
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: brand.ink,
              ),
            )
          else
            const Icon(Icons.play_arrow_rounded, size: 16),
          const SizedBox(width: 6),
          Text(
            running ? 'Running' : 'Run brief',
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _PipelineBreakdown extends StatelessWidget {
  const _PipelineBreakdown({
    required this.ready,
    required this.inputNeeded,
    required this.exploration,
  });

  final int ready;
  final int inputNeeded;
  final int exploration;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Row(
      children: [
        Expanded(
          child: _BreakdownTile(
            label: 'Ready',
            count: ready,
            color: brand.accent,
            fg: brand.onAccent,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _BreakdownTile(
            label: 'Needs input',
            count: inputNeeded,
            color: AppColors.categoryInput,
            fg: AppColors.ink,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _BreakdownTile(
            label: 'Strategic',
            count: exploration,
            color: AppColors.categoryExploreDeep,
            fg: Colors.white,
          ),
        ),
      ],
    );
  }
}

class _BreakdownTile extends StatelessWidget {
  const _BreakdownTile({
    required this.label,
    required this.count,
    required this.color,
    required this.fg,
  });

  final String label;
  final int count;
  final Color color;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$count',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: fg,
              height: 1,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.6,
              color: fg.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }
}
