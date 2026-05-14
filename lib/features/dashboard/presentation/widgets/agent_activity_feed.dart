import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../agent/state/passive_agent_controller.dart';

class AgentActivityFeed extends StatelessWidget {
  const AgentActivityFeed({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<PassiveAgentController>(
      builder: (context, controller, _) {
        final steps = controller.activity;
        if (steps.isEmpty) {
          return const _EmptyFeed();
        }
        return Column(
          children: [
            for (final activity in steps) _ActivityRow(activity: activity),
          ],
        );
      },
    );
  }
}

class _EmptyFeed extends StatelessWidget {
  const _EmptyFeed();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: const Row(
        children: [
          Icon(Icons.bolt_outlined, color: AppColors.textMuted, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Agent is idle. Run a brief to see activity here.',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.activity});

  final AgentActivityStep activity;

  @override
  Widget build(BuildContext context) {
    final status = activity.status;
    final undoable = activity.undoable;

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border.withValues(alpha: 0.60)),
        ),
        child: Stack(
          children: [
            if (status == 'active')
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Container(width: 4, color: AppColors.accent)
                    .animate(onPlay: (c) => c.repeat(reverse: true))
                    .fadeIn(duration: 800.ms)
                    .then()
                    .fadeOut(duration: 800.ms),
              ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _StatusIcon(status: status),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                activity.tool,
                                style: TextStyle(
                                  color: AppColors.ink.withValues(alpha: 0.40),
                                  fontSize: 10,
                                  letterSpacing: 1.4,
                                  fontWeight: FontWeight.w900,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                            Text(
                              _relative(activity.createdAt),
                              style: const TextStyle(
                                color: AppColors.textSoft,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          activity.detail,
                          style: const TextStyle(
                            color: AppColors.ink,
                            fontSize: 12,
                            height: 1.45,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (status == 'done' && undoable) ...[
                          const SizedBox(height: 10),
                          const _UndoButton(),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _relative(DateTime ts) {
    final diff = DateTime.now().difference(ts);
    if (diff.inSeconds < 30) return 'just now';
    if (diff.inMinutes < 1) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    IconData icon;
    bool pulse = false;

    switch (status) {
      case 'active':
        bg = AppColors.ink;
        fg = AppColors.accent;
        icon = Icons.bolt_rounded;
        pulse = true;
        break;
      case 'done':
        bg = AppColors.softSurface;
        fg = AppColors.ink;
        icon = Icons.check_circle_outline_rounded;
        break;
      default:
        bg = const Color(0xFFFEF3C7);
        fg = const Color(0xFFD97706);
        icon = Icons.access_time_rounded;
    }

    final iconWidget = Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 16, color: fg),
    );

    if (!pulse) return iconWidget;

    return iconWidget
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .scale(
          duration: 900.ms,
          begin: const Offset(1, 1),
          end: const Offset(1.06, 1.06),
          curve: Curves.easeInOut,
        );
  }
}

class _UndoButton extends StatelessWidget {
  const _UndoButton();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.softSurface,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: AppColors.border),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.undo_rounded, size: 12, color: AppColors.ink),
          SizedBox(width: 6),
          Text(
            'Undo Action',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}
