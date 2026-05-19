import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/router/route_names.dart';
import '../../../core/theme/brand_theme.dart';
import '../../../shared/widgets/app_header.dart';
import '../models/app_notification.dart';
import '../state/notifications_notifier.dart';

class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key});

  void _handleTap(BuildContext context, WidgetRef ref, AppNotification n) {
    ref.read(notificationsProvider.notifier).markRead(n.id);
    final route = switch (n.kind) {
      NotificationKind.intercept => RouteNames.jobs,
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
    ref.listen<NotificationsState>(notificationsProvider, (prev, next) {
      if (next.lastMessage == null || next.lastMessage == prev?.lastMessage) {
        return;
      }
      ref.read(notificationsProvider.notifier).consumeMessage();
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(next.lastMessage!)));
    });

    final state = ref.watch(notificationsProvider);
    final notifier = ref.read(notificationsProvider.notifier);
    final hasUnread = state.unreadCount > 0;
    final items = state.filtered;

    return Scaffold(
      backgroundColor: brand.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            AppHeader.page(
              title: AppStrings.notificationsTitle,
              onBack: () => context.go(RouteNames.dashboard),
              trailing: hasUnread
                  ? _ReadAllChip(onTap: notifier.markAllRead)
                  : null,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppConstants.screenHorizontalPadding,
                8,
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
                          onAction: () => _handleTap(context, ref, n),
                          onMarkRead: () => notifier.markRead(n.id),
                        )
                            .animate(delay: (i * 50).ms)
                            .fadeIn()
                            .moveY(begin: 8, end: 0);
                      },
                    ),
            ),
          ],
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
            border: Border.all(
              color: active ? brand.ink : brand.border,
            ),
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
              Icon(Icons.notifications_none_rounded,
                  size: 28, color: brand.textMuted),
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

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.notification,
    required this.onTap,
    required this.onAction,
    required this.onMarkRead,
  });

  final AppNotification notification;
  final VoidCallback onTap;
  final VoidCallback onAction;
  final VoidCallback onMarkRead;

  (IconData, Color, Color) _icon(BrandTheme brand) =>
      switch (notification.kind) {
        NotificationKind.intercept => (
            Icons.front_hand_outlined,
            brand.warning.withValues(alpha: 0.20),
            AppColors.categoryInputDeep,
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
            AppColors.categoryExplore.withValues(alpha: 0.20),
            AppColors.categoryExploreDeep,
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
                blurRadius: 16,
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
                    Row(
                      children: [
                        Text(
                          notification.timestamp,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: brand.textSoft,
                          ),
                        ),
                        if (notification.actionLabel != null) ...[
                          const SizedBox(width: 12),
                          _InlineAction(
                            label: notification.actionLabel!,
                            onTap: onAction,
                          ),
                        ],
                      ],
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

class _InlineAction extends StatelessWidget {
  const _InlineAction({required this.label, required this.onTap});

  final String label;
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
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: brand.ink,
            borderRadius: BorderRadius.circular(99),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: brand.inkInverse,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.arrow_forward_rounded,
                size: 12,
                color: brand.accent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
