import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/router/route_names.dart';
import '../../../data/mock/mock_notifications.dart';
import '../../../shared/widgets/app_header.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  late List<AppNotification> _items = List.of(MockNotifications.all);

  void _markAllRead() {
    setState(() {
      _items = _items
          .map((n) => AppNotification(
                id: n.id,
                kind: n.kind,
                title: n.title,
                body: n.body,
                timestamp: n.timestamp,
                actionLabel: n.actionLabel,
                unread: false,
              ))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasUnread = _items.any((n) => n.unread);
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            AppHeader.page(
              title: AppStrings.notificationsTitle,
              onBack: () => context.go(RouteNames.dashboard),
              trailing: hasUnread
                  ? _ReadAllChip(onTap: _markAllRead)
                  : null,
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(
                  AppConstants.screenHorizontalPadding,
                  16,
                  AppConstants.screenHorizontalPadding,
                  40,
                ),
                itemCount: _items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  return _NotificationCard(notification: _items[i])
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

class _ReadAllChip extends StatelessWidget {
  const _ReadAllChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: AppColors.border),
          ),
          child: const Text(
            AppStrings.markAllRead,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.notification});

  final AppNotification notification;

  (IconData, Color, Color) get _icon => switch (notification.kind) {
        NotificationKind.intercept => (
            Icons.front_hand_outlined,
            AppColors.warning.withValues(alpha: 0.20),
            AppColors.categoryInputDeep,
          ),
        NotificationKind.reply => (
            Icons.mark_email_unread_outlined,
            AppColors.accent.withValues(alpha: 0.30),
            AppColors.ink,
          ),
        NotificationKind.drafted => (
            Icons.edit_note_rounded,
            AppColors.softSurface,
            AppColors.ink,
          ),
        NotificationKind.undo => (
            Icons.undo_rounded,
            AppColors.softSurface,
            AppColors.ink,
          ),
        NotificationKind.match => (
            Icons.auto_awesome_rounded,
            AppColors.categoryExplore.withValues(alpha: 0.20),
            AppColors.categoryExploreDeep,
          ),
      };

  @override
  Widget build(BuildContext context) {
    final (icon, bg, fg) = _icon;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: notification.unread
              ? AppColors.ink.withValues(alpha: 0.15)
              : AppColors.border.withValues(alpha: 0.60),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
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
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                    if (notification.unread)
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: AppColors.danger,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  notification.body,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textMuted,
                    height: 1.45,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      notification.timestamp,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textSoft,
                      ),
                    ),
                    if (notification.actionLabel != null) ...[
                      const SizedBox(width: 12),
                      _InlineAction(label: notification.actionLabel!),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineAction extends StatelessWidget {
  const _InlineAction({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        onTap: () {},
        borderRadius: BorderRadius.circular(99),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.ink,
            borderRadius: BorderRadius.circular(99),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.arrow_forward_rounded,
                size: 12,
                color: AppColors.accent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
