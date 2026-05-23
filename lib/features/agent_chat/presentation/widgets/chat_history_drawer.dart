import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/brand_theme.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../auth/state/auth_notifier.dart';
import '../../models/conversation_summary.dart';
import '../../state/agent_chat_notifier.dart';
import 'profile_sheet.dart';

/// Unified left drawer for the chat. Replaces the legacy bottom-nav: holds
/// the Syncra wordmark + avatar (tap → profile sheet), the top-level
/// destinations (Resumes, Applications, Notifications), and the recents
/// chat list. A floating "New chat" pill sits at the bottom.
class ChatHistoryDrawer extends ConsumerWidget {
  const ChatHistoryDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final width = MediaQuery.sizeOf(context).width;
    final convos = ref.watch(conversationListProvider);
    final currentId =
        ref.watch(agentChatProvider.select((s) => s.conversationId));
    final notifier = ref.read(agentChatProvider.notifier);
    final initial = ref.watch(
      authProvider.select((s) => s.appUser?.initial ?? '?'),
    );

    return Drawer(
      backgroundColor: brand.bg,
      width: width * 0.86,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Column(
              children: [
                _DrawerHeader(
                  initial: initial,
                  onAvatarTap: () => ProfileSheet.show(context),
                ),
                _DrawerNavItem(
                  icon: Icons.description_outlined,
                  label: 'Resumes',
                  onTap: () {
                    Navigator.of(context).maybePop();
                    context.go(RouteNames.resumes);
                  },
                ),
                _DrawerNavItem(
                  icon: Icons.timeline_rounded,
                  label: 'Applications',
                  onTap: () {
                    Navigator.of(context).maybePop();
                    context.go(RouteNames.applications);
                  },
                ),
                _DrawerNavItem(
                  icon: Icons.notifications_outlined,
                  label: 'Notifications',
                  onTap: () {
                    Navigator.of(context).maybePop();
                    context.go(RouteNames.notifications);
                  },
                ),
                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppConstants.screenHorizontalPadding,
                    0,
                    AppConstants.screenHorizontalPadding,
                    8,
                  ),
                  child: Row(
                    children: [
                      Text(
                        'RECENTS',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.4,
                          color: brand.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: convos.when(
                    loading: () => const Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                    error: (_, _) => const _RecentsEmpty(),
                    data: (list) => list.isEmpty
                        ? const _RecentsEmpty()
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(
                              AppConstants.screenHorizontalPadding,
                              4,
                              AppConstants.screenHorizontalPadding,
                              96,
                            ),
                            itemCount: list.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 6),
                            itemBuilder: (context, i) {
                              final c = list[i];
                              return _ConversationRow(
                                summary: c,
                                active: c.id == currentId,
                                onTap: () {
                                  Navigator.of(context).maybePop();
                                  notifier.switchConversation(c.id);
                                },
                                onDelete: () =>
                                    _confirmDelete(context, ref, c),
                              )
                                  .animate(delay: (i * 30).ms)
                                  .fadeIn(duration: 220.ms)
                                  .moveX(begin: -10, end: 0);
                            },
                          ),
                  ),
                ),
              ],
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 18,
              child: Center(
                child: _NewChatPill(
                  onTap: () {
                    Navigator.of(context).maybePop();
                    notifier.newConversation();
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    ConversationSummary c,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete chat?'),
        content: Text('"${c.title}" will be permanently removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(agentChatProvider.notifier).deleteConversation(c.id);
    }
  }
}

class _DrawerHeader extends StatelessWidget {
  const _DrawerHeader({required this.initial, required this.onAvatarTap});

  final String initial;
  final VoidCallback onAvatarTap;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.screenHorizontalPadding,
        18,
        AppConstants.screenHorizontalPadding,
        16,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Syncra',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: brand.ink,
                letterSpacing: -0.8,
                height: 1,
              ),
            ),
          ),
          Semantics(
            label: 'Account',
            button: true,
            child: Material(
              color: brand.surfaceMuted,
              shape: CircleBorder(
                side: BorderSide(
                  color: brand.border.withValues(alpha: 0.7),
                  width: 1,
                ),
              ),
              child: InkWell(
                onTap: onAvatarTap,
                customBorder: const CircleBorder(),
                child: SizedBox(
                  width: 38,
                  height: 38,
                  child: Center(
                    child: Text(
                      initial,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: brand.ink,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DrawerNavItem extends StatelessWidget {
  const _DrawerNavItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.screenHorizontalPadding,
            vertical: 12,
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: brand.ink),
              const SizedBox(width: 14),
              Text(
                label,
                style: TextStyle(
                  color: brand.ink,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NewChatPill extends StatelessWidget {
  const _NewChatPill({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Material(
      color: brand.ink,
      shape: const StadiumBorder(),
      elevation: 8,
      shadowColor: brand.shadow.withValues(alpha: 0.35),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_rounded, size: 18, color: brand.inkInverse),
              const SizedBox(width: 8),
              Text(
                'New chat',
                style: TextStyle(
                  color: brand.inkInverse,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConversationRow extends StatelessWidget {
  const _ConversationRow({
    required this.summary,
    required this.active,
    required this.onTap,
    required this.onDelete,
  });

  final ConversationSummary summary;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Material(
      color: active ? brand.surface : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: active
                ? Border.all(color: brand.border, width: 1)
                : null,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      summary.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: brand.ink,
                        letterSpacing: -0.15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      DateFormatter.relativeShort(summary.updatedAt),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: brand.textSoft,
                      ),
                    ),
                  ],
                ),
              ),
              Semantics(
                label: 'Delete chat',
                button: true,
                child: InkResponse(
                  onTap: onDelete,
                  radius: 22,
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: Icon(
                      Icons.delete_outline_rounded,
                      size: 17,
                      color: brand.textSoft,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentsEmpty extends StatelessWidget {
  const _RecentsEmpty();

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.screenHorizontalPadding,
        vertical: 12,
      ),
      child: Text(
        'No chats yet.',
        style: TextStyle(
          fontSize: 13,
          color: brand.textMuted,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
