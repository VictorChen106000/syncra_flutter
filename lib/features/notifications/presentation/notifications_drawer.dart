import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/router/route_names.dart';
import '../../../core/theme/brand_theme.dart';
import '../models/app_notification.dart';
import '../state/notifications_notifier.dart';
import 'package:flutter_riverpod/legacy.dart';

/// `true` while the dashboard's left drawer is on screen. The shell
/// scaffold reads this to slide its floating bottom nav out of the way.
final notificationsDrawerOpenProvider = StateProvider<bool>((ref) => false);

/// Slide-in left drawer that replaces the legacy notification bell route.
/// Opened by tapping the dashboard avatar or by swiping from the left edge.
class NotificationsDrawer extends ConsumerWidget {
  const NotificationsDrawer({super.key});

  void _handleTap(BuildContext context, WidgetRef ref, AppNotification n) {
    ref.read(notificationsProvider.notifier).markRead(n.id);
    Navigator.of(context).maybePop();
    final route = switch (n.kind) {
      NotificationKind.intercept => RouteNames.agentChat,
      NotificationKind.proposal => RouteNames.agentChat,
      NotificationKind.reply => RouteNames.agentChat,
      NotificationKind.drafted => RouteNames.jobs,
      NotificationKind.undo => RouteNames.jobs,
      NotificationKind.match => RouteNames.jobs,
    };
    context.go(route);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final state = ref.watch(notificationsProvider);
    final notifier = ref.read(notificationsProvider.notifier);
    final items = state.filtered;
    final hasUnread = state.unreadCount > 0;
    final width = MediaQuery.sizeOf(context).width;

    return Drawer(
      backgroundColor: brand.bg,
      width: width * 0.88,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _DrawerHeader(
              unreadCount: state.unreadCount,
              onMarkAllRead: hasUnread ? notifier.markAllRead : null,
              onClose: () => Navigator.of(context).maybePop(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppConstants.screenHorizontalPadding,
                4,
                AppConstants.screenHorizontalPadding,
                8,
              ),
              child: _FilterTabs(
                filter: state.filter,
                unreadCount: state.unreadCount,
                onChanged: notifier.setFilter,
              ),
            ),
            Expanded(
              child: items.isEmpty
                  ? _EmptyState(hasAnyEver: state.items.isNotEmpty)
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(
                        AppConstants.screenHorizontalPadding,
                        8,
                        AppConstants.screenHorizontalPadding,
                        40,
                      ),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final n = items[i];
                        return _NotificationCard(
                              notification: n,
                              onTap: () => _handleTap(context, ref, n),
                              onMarkRead: () => notifier.markRead(n.id),
                            )
                            .animate(delay: (i * 40).ms)
                            .fadeIn(duration: 240.ms)
                            .moveX(begin: -10, end: 0);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerHeader extends StatelessWidget {
  const _DrawerHeader({
    required this.unreadCount,
    required this.onMarkAllRead,
    required this.onClose,
  });

  final int unreadCount;
  final VoidCallback? onMarkAllRead;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.screenHorizontalPadding,
        16,
        AppConstants.screenHorizontalPadding,
        14,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppStrings.notificationsTitle,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: brand.ink,
                        letterSpacing: -0.6,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      unreadCount > 0 ? '$unreadCount unread' : 'All caught up',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: brand.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (onMarkAllRead != null) ...[
                _ReadAllChip(onTap: onMarkAllRead!),
                const SizedBox(width: 8),
              ],
              _CloseButton(onTap: onClose),
            ],
          ),
        ],
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Material(
      color: brand.surface,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(Icons.close_rounded, size: 18, color: brand.ink),
        ),
      ),
    );
  }
}

class _ReadAllChip extends StatelessWidget {
  const _ReadAllChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: brand.surface,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: brand.border),
          ),
          child: Text(
            AppStrings.markAllRead,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: brand.ink,
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterTabs extends StatelessWidget {
  const _FilterTabs({
    required this.filter,
    required this.unreadCount,
    required this.onChanged,
  });

  final NotificationsFilter filter;
  final int unreadCount;
  final ValueChanged<NotificationsFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _TabChip(
          label: 'All',
          active: filter == NotificationsFilter.all,
          onTap: () => onChanged(NotificationsFilter.all),
        ),
        const SizedBox(width: 8),
        _TabChip(
          label: unreadCount > 0 ? 'Unread · $unreadCount' : 'Unread',
          active: filter == NotificationsFilter.unread,
          onTap: () => onChanged(NotificationsFilter.unread),
        ),
      ],
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Material(
      color: active ? brand.ink : brand.surface,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: active ? brand.ink : brand.border),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: active ? brand.inkInverse : brand.ink,
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasAnyEver});

  final bool hasAnyEver;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final title = hasAnyEver ? "You're all caught up" : 'Nothing here yet';
    final body = hasAnyEver
        ? 'Switch to "All" to see your history.'
        : 'Once the agent starts working, you\'ll see its asks and '
              'completed actions here.';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: brand.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: brand.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.notifications_none_rounded,
                size: 28,
                color: brand.textMuted,
              ),
              const SizedBox(height: 10),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: brand.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                body,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: brand.textMuted,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.notification,
    required this.onTap,
    required this.onMarkRead,
  });

  final AppNotification notification;
  final VoidCallback onTap;
  final VoidCallback onMarkRead;

  (IconData, Color, Color) _icon(BrandTheme brand) =>
      switch (notification.kind) {
        NotificationKind.intercept => (
          Icons.front_hand_outlined,
          brand.accent.withValues(alpha: 0.20),
          brand.ink,
        ),
        NotificationKind.proposal => (
          Icons.task_alt_rounded,
          brand.accent.withValues(alpha: 0.20),
          brand.ink,
        ),
        NotificationKind.reply => (
          Icons.mark_email_unread_outlined,
          brand.accent.withValues(alpha: 0.30),
          brand.ink,
        ),
        NotificationKind.drafted => (
          Icons.edit_note_rounded,
          brand.surfaceMuted,
          brand.ink,
        ),
        NotificationKind.undo => (
          Icons.undo_rounded,
          brand.surfaceMuted,
          brand.ink,
        ),
        NotificationKind.match => (
          Icons.auto_awesome_rounded,
          brand.accent.withValues(alpha: 0.20),
          brand.ink,
        ),
      };

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final (icon, bg, fg) = _icon(brand);
    return Material(
      color: brand.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: notification.unread
                  ? brand.ink.withValues(alpha: 0.15)
                  : brand.border.withValues(alpha: 0.60),
            ),
            boxShadow: [
              BoxShadow(
                color: brand.shadow,
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 18, color: fg),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            notification.title,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              color: brand.ink,
                            ),
                          ),
                        ),
                        if (notification.unread)
                          InkResponse(
                            onTap: onMarkRead,
                            radius: 14,
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: brand.danger,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      notification.body,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: brand.textMuted,
                        height: 1.45,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      notification.timestamp,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: brand.textSoft,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
