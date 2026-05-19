import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/brand_theme.dart';
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
    this.leadingGap = 12,
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
      titleWidget: _HomeTitle(name: name, role: role),
      trailing: NotificationBell(
        onTap: onBellTap,
        showDot: unreadCount > 0,
      ),
      bottom: bottom,
      topPadding: 16,
      bottomPadding: 16,
      leadingGap: 14,
    );
  }

  /// Bottom-nav tab page — clean title with optional trailing widget.
  factory AppHeader.tab({
    required String title,
    String? subtitle,
    Widget? trailing,
    Widget? bottom,
  }) {
    return AppHeader._(
      titleWidget: _TabTitle(title: title, subtitle: subtitle),
      trailing: trailing,
      bottom: bottom,
      topPadding: 18,
      bottomPadding: bottom == null ? 18 : 14,
    );
  }

  /// Pushed page — back arrow + leading title with optional kicker.
  factory AppHeader.page({
    required String title,
    String? kicker,
    VoidCallback? onBack,
    Widget? trailing,
    Widget? bottom,
  }) {
    return AppHeader._(
      leading: AppBackButton(onPressed: onBack),
      titleWidget: _PageTitle(title: title, kicker: kicker),
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
  final double leadingGap;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Container(
      color: brand.bg,
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
              if (leading != null && titleWidget != null)
                SizedBox(width: leadingGap),
              if (titleWidget != null) Expanded(child: titleWidget!),
              ?trailing,
            ],
          ),
          if (bottom != null) ...[
            const SizedBox(height: 18),
            bottom!,
          ],
        ],
      ),
    );
  }
}

class _HomeTitle extends StatelessWidget {
  const _HomeTitle({required this.name, required this.role});
  final String name;
  final String role;
  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: brand.ink,
            fontSize: 24,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
            height: 1.05,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          role,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: brand.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
        ),
      ],
    );
  }
}

class _TabTitle extends StatelessWidget {
  const _TabTitle({required this.title, this.subtitle});
  final String title;
  final String? subtitle;
  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w900,
            color: brand.ink,
            letterSpacing: -0.6,
            height: 1,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          Text(
            subtitle!,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: brand.textMuted,
              height: 1.45,
            ),
          ),
        ],
      ],
    );
  }
}

class _PageTitle extends StatelessWidget {
  const _PageTitle({required this.title, this.kicker});
  final String title;
  final String? kicker;
  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (kicker != null) ...[
            Text(
              kicker!.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: brand.textMuted,
                letterSpacing: 1.4,
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
              color: brand.ink,
              letterSpacing: -0.4,
              height: 1.05,
            ),
          ),
        ],
      ),
    );
  }
}
