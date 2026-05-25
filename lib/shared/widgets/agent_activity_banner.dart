import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/router/app_router.dart';
import '../../core/router/route_names.dart';
import '../../core/theme/brand_theme.dart';
import '../../features/agent_chat/state/agent_chat_notifier.dart';
import '../../features/notifications/models/app_notification.dart';
import '../../features/notifications/state/notifications_notifier.dart';

/// Top-of-screen banner that surfaces the most recent **actionable** agent
/// notification (intercepts, proposals, drafts, undo). Slides in from the
/// top and lets the user accept / answer / dismiss without leaving the
/// current page.
///
/// Rendered globally by [AppShellScaffold] so it floats over whichever tab
/// is active. When no agent activity needs attention, it renders nothing.
/// Takes priority over the running-task pill — see [RunningTaskBanner], which
/// yields its slot when an intercept/proposal is unread.
class AgentActivityBanner extends ConsumerWidget {
  const AgentActivityBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(notificationsProvider);
    final active = _pickActive(notifications.items);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SizeTransition(
            sizeFactor: animation,
            axisAlignment: -1.0,
            child: child,
          ),
        );
      },
      child: active == null
          ? const SizedBox.shrink(key: ValueKey('empty'))
          : _BannerCard(
              key: ValueKey(active.id),
              notification: active,
              onPrimary: () => _onPrimary(ref, active),
              onSecondary: () => _onSecondary(ref, active),
              onDismiss: () => ref
                  .read(notificationsProvider.notifier)
                  .markRead(active.id),
            ),
    );
  }

  /// Primary action: for a proposal, accept the underlying chat block; for
  /// every other kind, mark it read (and the banner card's surrounding tap
  /// already routes to the chat where appropriate).
  void _onPrimary(WidgetRef ref, AppNotification n) {
    final blockId = n.targetBlockId;
    if (n.kind == NotificationKind.proposal && blockId != null) {
      ref.read(agentChatProvider.notifier).acceptProposal(blockId);
      return;
    }
    if (n.kind == NotificationKind.intercept && blockId != null) {
      // ask_user needs a typed answer — route to the chat where the docked
      // input field lives. Mark read once we're heading there.
      ref.read(notificationsProvider.notifier).markRead(n.id);
      ref.read(routerProvider).go(RouteNames.agentChat);
      return;
    }
    ref.read(notificationsProvider.notifier).markRead(n.id);
  }

  /// Secondary action: for a proposal, "Make changes" dismisses the proposal
  /// the same way the docked card does; for every other kind, the secondary
  /// is a plain "Later" dismiss.
  void _onSecondary(WidgetRef ref, AppNotification n) {
    final blockId = n.targetBlockId;
    if (n.kind == NotificationKind.proposal && blockId != null) {
      ref.read(agentChatProvider.notifier).dismissProposal(blockId);
      return;
    }
    ref.read(notificationsProvider.notifier).markRead(n.id);
  }

  /// Pick the highest-priority unread entry to surface. Intercept and
  /// proposal both block the agent on the user — surface those first so the
  /// loop can resume without the user opening the chat. Drafts/matches sit
  /// underneath as soft surfacing.
  static AppNotification? _pickActive(List<AppNotification> items) {
    AppNotification? bestFor(NotificationKind kind) {
      for (final n in items) {
        if (n.unread && n.kind == kind) return n;
      }
      return null;
    }

    // The top banner is reserved for blocking events only: an `ask_user`
    // (intercept) or an Accept/Make-changes proposal. Other kinds stay in
    // the inbox drawer so the user isn't nagged with passive "draft ready"
    // pills they have to dismiss.
    return bestFor(NotificationKind.intercept) ??
        bestFor(NotificationKind.proposal);
  }
}

class _BannerCard extends StatelessWidget {
  const _BannerCard({
    super.key,
    required this.notification,
    required this.onPrimary,
    required this.onSecondary,
    required this.onDismiss,
  });

  final AppNotification notification;
  final VoidCallback onPrimary;

  /// Secondary action — used by [NotificationKind.proposal] to expose
  /// "Make changes" inline. Falls back to a plain "Later" dismiss for kinds
  /// that don't carry a secondary label.
  final VoidCallback onSecondary;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final isDark = brand.isDark;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Material(
          color: Colors.transparent,
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _PulsingAgentDot(),
                    const SizedBox(width: 10),
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
                                _kindLabel(notification.kind),
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
                            notification.title,
                            style: TextStyle(
                              color: brand.ink,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.2,
                              height: 1.25,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            notification.body,
                            style: TextStyle(
                              color: brand.textMuted,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                              height: 1.45,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    _DismissChip(onTap: onDismiss),
                  ],
                ),
                const SizedBox(height: 12),
                _BannerActions(
                  notification: notification,
                  onPrimary: onPrimary,
                  onSecondary: onSecondary,
                  onDismiss: onDismiss,
                ),
              ],
            ),
          ),
        ),
      ),
    )
        .animate()
        .fadeIn(duration: 220.ms)
        .moveY(begin: -14, end: 0, curve: Curves.easeOutCubic);
  }

  static String _kindLabel(NotificationKind kind) {
    return switch (kind) {
      NotificationKind.intercept => '· NEEDS INPUT',
      NotificationKind.proposal => '· NEEDS YOUR OK',
      NotificationKind.drafted => '· DRAFT READY',
      NotificationKind.undo => '· REVERSIBLE',
      NotificationKind.match => '· NEW MATCH',
      NotificationKind.reply => '· REPLY',
    };
  }
}

/// Action row beneath the banner body. Proposals get two equal-weight pills
/// (Accept + Make changes) so the user can settle the chat block from here.
/// Everything else collapses back to a primary pill + a "Later" dismiss.
class _BannerActions extends StatelessWidget {
  const _BannerActions({
    required this.notification,
    required this.onPrimary,
    required this.onSecondary,
    required this.onDismiss,
  });

  final AppNotification notification;
  final VoidCallback onPrimary;
  final VoidCallback onSecondary;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final isProposal = notification.kind == NotificationKind.proposal;
    final primaryLabel = notification.actionLabel ?? 'Open';
    if (isProposal) {
      final secondaryLabel = notification.secondaryActionLabel ?? 'Make changes';
      return Row(
        children: [
          Expanded(
            child: _SecondaryAction(
              label: secondaryLabel,
              onTap: onSecondary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _PrimaryAction(
              label: primaryLabel,
              onTap: onPrimary,
            ),
          ),
        ],
      );
    }
    return Row(
      children: [
        Expanded(
          child: _PrimaryAction(
            label: primaryLabel,
            onTap: onPrimary,
          ),
        ),
        const SizedBox(width: 8),
        _SecondaryAction(
          label: 'Later',
          onTap: onDismiss,
        ),
      ],
    );
  }
}

class _PulsingAgentDot extends StatelessWidget {
  const _PulsingAgentDot();

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Container(
      width: 10,
      height: 10,
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: brand.accent,
        shape: BoxShape.circle,
      ),
    )
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .fadeIn(begin: 0.4, duration: 900.ms, curve: Curves.easeInOut);
  }
}

class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Material(
      color: brand.accent,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Container(
          height: 38,
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: brand.onAccent,
              fontWeight: FontWeight.w900,
              fontSize: 13,
              letterSpacing: -0.1,
            ),
          ),
        ),
      ),
    );
  }
}

class _SecondaryAction extends StatelessWidget {
  const _SecondaryAction({required this.label, required this.onTap});
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
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: brand.ink,
              fontWeight: FontWeight.w800,
              fontSize: 13,
              letterSpacing: -0.1,
            ),
          ),
        ),
      ),
    );
  }
}

class _DismissChip extends StatelessWidget {
  const _DismissChip({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
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
