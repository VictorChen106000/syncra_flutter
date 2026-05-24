import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/router/app_router.dart';
import '../../core/router/route_names.dart';
import '../../core/theme/brand_theme.dart';
import '../../features/notifications/models/app_notification.dart';
import '../../features/notifications/state/notifications_notifier.dart';
import '../state/running_task_notifier.dart';

/// A global status card that floats at the top of the app while a background
/// task (an agent prompt, a resume tailor, …) is in flight.
///
/// Mounted once in `SyncraApp`'s `MaterialApp.router` builder so it overlays
/// *every* route — the task keeps running and the card stays visible no
/// matter where the user navigates. Reads [runningTaskProvider]; renders
/// nothing when idle. Tapping it jumps to the agent chat.
///
/// Sized to match the actionable [AgentActivityBanner] card so the two top
/// banners feel like one consistent surface.
class RunningTaskBanner extends ConsumerWidget {
  const RunningTaskBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final task = ref.watch(runningTaskProvider);
    final router = ref.watch(routerProvider);
    // Yield to a pending intercept/proposal so the user-facing "needs action"
    // banner gets the top slot — the running pill is informational, those
    // are blocking.
    final hasActionable = ref.watch(notificationsProvider).items.any(
          (n) =>
              n.unread &&
              (n.kind == NotificationKind.intercept ||
                  n.kind == NotificationKind.proposal),
        );
    // Rebuild on every route change so the RUNNING card can hide itself on
    // the page the task came from. Terminal (DONE/FAILED) states ignore the
    // suppression so the result is never missed.
    return ListenableBuilder(
      listenable: router.routerDelegate,
      builder: (context, _) {
        final location =
            router.routerDelegate.currentConfiguration.uri.path;
        final isRunning = task.status == RunningTaskStatus.running;
        final suppressForOrigin =
            isRunning && task.originRoutes.contains(location);
        final suppressForActionable = isRunning && hasActionable;
        final visible = task.isActive &&
            !suppressForOrigin &&
            !suppressForActionable;
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
          child: visible
              ? _TaskCard(
                  // Key on the status so the card animates on running →
                  // completed, but updates in place for label-only changes.
                  key: ValueKey(task.status),
                  task: task,
                  onTap: () =>
                      ref.read(routerProvider).go(RouteNames.agentChat),
                  onDismiss: () =>
                      ref.read(runningTaskProvider.notifier).dismiss(),
                )
              : const SizedBox.shrink(key: ValueKey('idle')),
        );
      },
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
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
    final isDark = brand.isDark;
    final accent = switch (task.status) {
      RunningTaskStatus.completed => brand.success,
      RunningTaskStatus.failed => brand.danger,
      _ => brand.accent,
    };
    final eyebrow = switch (task.status) {
      RunningTaskStatus.completed => 'DONE',
      RunningTaskStatus.failed => 'FAILED',
      _ => 'RUNNING',
    };
    final body = (task.detail != null && task.detail!.isNotEmpty)
        ? task.detail!
        : switch (task.status) {
            RunningTaskStatus.completed => 'Tap to view the result.',
            RunningTaskStatus.failed =>
              'Something went wrong — tap to open and retry.',
            _ => 'Running in the background — tap to open the chat.',
          };

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              decoration: BoxDecoration(
                color: isDark
                    ? brand.surface.withValues(alpha: 0.96)
                    : brand.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: brand.border),
                boxShadow: [
                  BoxShadow(
                    color: brand.shadow,
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _StatusBadge(status: task.status, accent: accent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'AGENT',
                              style: TextStyle(
                                color: brand.accent,
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.4,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '· $eyebrow',
                              style: TextStyle(
                                color: brand.textMuted,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          task.label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: brand.ink,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: brand.textMuted,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            height: 1.45,
                          ),
                        ),
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
    )
        .animate()
        .fadeIn(duration: 220.ms)
        .moveY(begin: -14, end: 0, curve: Curves.easeOutCubic);
  }
}

/// The leading glyph: a rounded badge with a spinning ring while running, or
/// a settled status icon once the task is done or failed.
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status, required this.accent});

  final RunningTaskStatus status;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    Widget icon;
    if (status == RunningTaskStatus.running) {
      icon = Icon(Icons.autorenew_rounded, size: 20, color: accent)
          .animate(onPlay: (c) => c.repeat())
          .rotate(duration: 900.ms, curve: Curves.linear);
    } else {
      icon = Icon(
        status == RunningTaskStatus.completed
            ? Icons.check_circle_rounded
            : Icons.error_rounded,
        size: 20,
        color: accent,
      );
    }
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: icon,
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
