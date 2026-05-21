import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/router/app_router.dart';
import '../../core/router/route_names.dart';
import '../../core/theme/brand_theme.dart';
import '../state/running_task_notifier.dart';

/// A slim, global status pill that floats at the very top of the app while a
/// background task (an agent prompt, a resume tailor, …) is in flight.
///
/// Mounted once in `SyncraApp`'s `MaterialApp.router` builder so it overlays
/// *every* route — the task keeps running and the pill stays visible no
/// matter where the user navigates. Reads [runningTaskProvider]; renders
/// nothing when idle. Tapping it jumps to the agent chat.
class RunningTaskBanner extends ConsumerWidget {
  const RunningTaskBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final task = ref.watch(runningTaskProvider);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SizeTransition(
          sizeFactor: animation,
          axisAlignment: -1,
          child: child,
        ),
      ),
      child: task.isActive
          ? _TaskPill(
              // Key on the status so the pill animates on running → completed,
              // but updates in place for label-only changes.
              key: ValueKey(task.status),
              task: task,
              onTap: () => ref.read(routerProvider).go(RouteNames.agentChat),
              onDismiss: () =>
                  ref.read(runningTaskProvider.notifier).dismiss(),
            )
          : const SizedBox.shrink(key: ValueKey('idle')),
    );
  }
}

class _TaskPill extends StatelessWidget {
  const _TaskPill({
    super.key,
    required this.task,
    required this.onTap,
    required this.onDismiss,
  });

  final RunningTaskState task;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final accent = switch (task.status) {
      RunningTaskStatus.completed => brand.success,
      RunningTaskStatus.failed => brand.danger,
      _ => brand.accent,
    };

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(99),
                child: Container(
                  decoration: BoxDecoration(
                    color: brand.isDark
                        ? brand.surface.withValues(alpha: 0.97)
                        : brand.surface,
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: brand.border),
                    boxShadow: [
                      BoxShadow(
                        color: brand.shadow,
                        blurRadius: 22,
                        offset: const Offset(0, 9),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.fromLTRB(14, 9, 8, 9),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _StatusIcon(status: task.status, color: accent),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              task.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: brand.ink,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.1,
                              ),
                            ),
                            if (task.detail != null &&
                                task.detail!.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                task.detail!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: brand.textMuted,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      _DismissButton(onTap: onDismiss),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    )
        .animate()
        .fadeIn(duration: 220.ms)
        .moveY(begin: -12, end: 0, curve: Curves.easeOutCubic);
  }
}

/// Status glyph: a spinning ring while running, a settled icon once terminal.
class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.status, required this.color});

  final RunningTaskStatus status;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (status == RunningTaskStatus.running) {
      return Icon(Icons.autorenew_rounded, size: 18, color: color)
          .animate(onPlay: (c) => c.repeat())
          .rotate(duration: 900.ms, curve: Curves.linear);
    }
    return Icon(
      status == RunningTaskStatus.completed
          ? Icons.check_circle_rounded
          : Icons.error_rounded,
      size: 18,
      color: color,
    );
  }
}

class _DismissButton extends StatelessWidget {
  const _DismissButton({required this.onTap});

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
        child: Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          child: Icon(
            Icons.close_rounded,
            size: 16,
            color: brand.textMuted,
          ),
        ),
      ),
    );
  }
}
