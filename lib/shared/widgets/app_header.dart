import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_constants.dart';
import 'app_back_button.dart';
import 'notification_bell.dart';

/// Single source of truth for the top-of-page chrome.
///
/// Use [AppHeader.home] on the dashboard (avatar + greeting + bell).
/// Use [AppHeader.tab] on bottom-nav pages (clean title only).
/// Use [AppHeader.page] on pushed/detail pages (back + title).
class AppHeader extends StatelessWidget {
  const AppHeader._({
    this.leading,
    this.titleWidget,
    this.trailing,
    this.bottom,
    this.bottomPadding = 16,
    this.topPadding = 14,
  });

  /// Home (Dashboard) — avatar + name/role + notification bell.
  factory AppHeader.home({
    required Widget avatar,
    required String name,
    required String role,
    required VoidCallback onBellTap,
    int unreadCount = 0,
    Widget? bottom,
  }) {
    return AppHeader._(
      leading: avatar,
      titleWidget: Padding(
        padding: const EdgeInsets.only(left: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              name,
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 20,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.3,
                height: 1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              role,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
      trailing: NotificationBell(
        onTap: onBellTap,
        showDot: unreadCount > 0,
      ),
      bottom: bottom,
      bottomPadding: bottom == null ? 16 : 14,
    );
  }

  /// Bottom-nav tab page — clean title with optional trailing widget.
  /// No back arrow, no bell.
  factory AppHeader.tab({
    required String title,
    String? subtitle,
    Widget? trailing,
    Widget? bottom,
  }) {
    return AppHeader._(
      titleWidget: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: AppColors.ink,
              letterSpacing: -0.6,
              height: 1,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.textMuted,
                height: 1.45,
              ),
            ),
          ],
        ],
      ),
      trailing: trailing,
      bottom: bottom,
      topPadding: 18,
      bottomPadding: bottom == null ? 18 : 14,
    );
  }

  /// Pushed page — back arrow + centered/leading title.
  /// Kicker is a small uppercase label above the title (e.g. company name).
  factory AppHeader.page({
    required String title,
    String? kicker,
    VoidCallback? onBack,
    Widget? trailing,
    Widget? bottom,
  }) {
    return AppHeader._(
      leading: AppBackButton(onPressed: onBack),
      titleWidget: Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (kicker != null) ...[
              Text(
                kicker.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textMuted,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 4),
            ],
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: kicker == null ? 20 : 19,
                fontWeight: FontWeight.w900,
                color: AppColors.ink,
                letterSpacing: -0.4,
                height: 1.05,
              ),
            ),
          ],
        ),
      ),
      trailing: trailing,
      bottom: bottom,
      bottomPadding: bottom == null ? 14 : 12,
    );
  }

  final Widget? leading;
  final Widget? titleWidget;
  final Widget? trailing;
  final Widget? bottom;
  final double bottomPadding;
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.scaffold,
        border: Border(
          bottom: BorderSide(color: AppColors.border.withValues(alpha: 0.50)),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        AppConstants.screenHorizontalPadding,
        topPadding,
        AppConstants.screenHorizontalPadding,
        bottomPadding,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ?leading,
              if (titleWidget != null) Expanded(child: titleWidget!),
              ?trailing,
            ],
          ),
          if (bottom != null) ...[
            const SizedBox(height: 14),
            bottom!,
          ],
        ],
      ),
    );
  }
}
