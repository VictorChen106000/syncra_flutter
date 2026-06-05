import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/brand_theme.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../models/conversation_summary.dart';
import '../../state/agent_chat_notifier.dart';

/// Left drawer on the chat page: a list of saved conversations. Tap a row to
/// reopen it; "New chat" starts fresh. Swipe from the left edge to open.
class ChatHistoryDrawer extends ConsumerWidget {
  const ChatHistoryDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final width = MediaQuery.sizeOf(context).width;
    final convos = ref.watch(conversationListProvider);
    final currentId = ref.watch(
      agentChatProvider.select((s) => s.conversationId),
    );
    final notifier = ref.read(agentChatProvider.notifier);

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
        child: Column(
          children: [
            _Header(onClose: () => Navigator.of(context).maybePop()),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppConstants.screenHorizontalPadding,
                4,
                AppConstants.screenHorizontalPadding,
                12,
              ),
              child: _NewChatButton(
                onTap: () {
                  Navigator.of(context).maybePop();
                  notifier.newConversation();
                },
              ),
            ),
            Expanded(
              child: convos.when(
                loading: () => const _LoadingState(),
                error: (_, _) => const _ErrorState(),
                data: (list) => list.isEmpty
                    ? const _EmptyState()
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(
                          AppConstants.screenHorizontalPadding,
                          4,
                          AppConstants.screenHorizontalPadding,
                          40,
                        ),
                        itemCount: list.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final c = list[i];
                          return _ConversationRow(
                                summary: c,
                                active: c.id == currentId,
                                onTap: () {
                                  Navigator.of(context).maybePop();
                                  notifier.switchConversation(c.id);
                                },
                                onDelete: () => _confirmDelete(context, ref, c),
                              )
                              .animate(delay: (i * 35).ms)
                              .fadeIn(duration: 220.ms)
                              .moveX(begin: -10, end: 0);
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

class _Header extends StatelessWidget {
  const _Header({required this.onClose});

  final VoidCallback onClose;

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
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: brand.accentMuted,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: brand.accent.withValues(
                  alpha: brand.isDark ? 0.28 : 0.5,
                ),
              ),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.history_rounded, size: 21, color: brand.ink),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Chat history',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: brand.ink,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Saved Syncra conversations',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: brand.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Semantics(
            label: 'Close',
            button: true,
            child: Material(
              color: brand.surface,
              shape: CircleBorder(side: BorderSide(color: brand.border)),
              child: InkWell(
                onTap: onClose,
                customBorder: const CircleBorder(),
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(Icons.close_rounded, size: 18, color: brand.ink),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NewChatButton extends StatelessWidget {
  const _NewChatButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: brand.accent.withValues(alpha: brand.isDark ? 0.16 : 0.24),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: brand.accent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          splashColor: brand.onAccent.withValues(alpha: 0.08),
          highlightColor: brand.onAccent.withValues(alpha: 0.04),
          child: SizedBox(
            height: 52,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_rounded, size: 20, color: brand.onAccent),
                const SizedBox(width: 8),
                Text(
                  'New chat',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w900,
                    color: brand.onAccent,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ConversationRow extends StatefulWidget {
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
  State<_ConversationRow> createState() => _ConversationRowState();
}

class _ConversationRowState extends State<_ConversationRow> {
  bool _rowHovered = false;
  bool _deleteHovered = false;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final active = widget.active;
    final rowRadius = BorderRadius.circular(18);
    final deleteColor = _deleteHovered
        ? brand.danger
        : brand.textSoft.withValues(alpha: brand.isDark ? 0.72 : 0.58);

    return MouseRegion(
      onEnter: (_) => setState(() => _rowHovered = true),
      onExit: (_) => setState(() {
        _rowHovered = false;
        _deleteHovered = false;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: active ? brand.accentMuted : brand.surface,
          borderRadius: rowRadius,
          border: Border.all(
            color: active
                ? brand.accent.withValues(alpha: brand.isDark ? 0.7 : 0.95)
                : (_rowHovered ? brand.outline : brand.border),
            width: active ? 1.4 : 1,
          ),
          boxShadow: [
            if (active || _rowHovered)
              BoxShadow(
                color: active
                    ? brand.accent.withValues(alpha: brand.isDark ? 0.12 : 0.16)
                    : brand.shadow,
                blurRadius: active ? 16 : 12,
                offset: const Offset(0, 8),
              ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: rowRadius,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: rowRadius,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    curve: Curves.easeOutCubic,
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: active ? brand.accent : brand.surfaceMuted,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: active
                            ? brand.accentBright
                            : brand.border.withValues(alpha: 0.7),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 17,
                      color: active ? brand.onAccent : brand.textMuted,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.summary.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.18,
                            fontWeight: FontWeight.w900,
                            color: brand.ink,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.schedule_rounded,
                              size: 13,
                              color: brand.textSoft,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                DateFormatter.relativeShort(
                                  widget.summary.updatedAt,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: brand.textMuted,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  MouseRegion(
                    onEnter: (_) => setState(() => _deleteHovered = true),
                    onExit: (_) => setState(() => _deleteHovered = false),
                    child: Semantics(
                      label: 'Delete chat',
                      button: true,
                      child: Tooltip(
                        message: 'Delete chat',
                        child: InkResponse(
                          onTap: widget.onDelete,
                          radius: 22,
                          hoverColor: brand.danger.withValues(alpha: 0.08),
                          highlightColor: brand.danger.withValues(alpha: 0.1),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 120),
                            curve: Curves.easeOutCubic,
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: _deleteHovered
                                  ? brand.danger.withValues(
                                      alpha: brand.isDark ? 0.14 : 0.08,
                                    )
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            alignment: Alignment.center,
                            child: Icon(
                              Icons.delete_outline_rounded,
                              size: 18,
                              color: deleteColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            color: brand.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: brand.border),
            boxShadow: [
              BoxShadow(
                color: brand.shadow,
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: brand.accent,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Loading chats',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: brand.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return _StatusCard(
      icon: Icons.forum_outlined,
      iconColor: brand.ink,
      iconBackground: brand.accentMuted,
      title: 'No saved chats yet',
      message:
          'Saved Syncra conversations will appear here after you send a message.',
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState();

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return _StatusCard(
      icon: Icons.error_outline_rounded,
      iconColor: brand.warning,
      iconBackground: brand.warning.withValues(
        alpha: brand.isDark ? 0.14 : 0.1,
      ),
      title: "Couldn't load chats",
      message:
          'Saved conversations are still safe. Try reopening the drawer in a moment.',
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: brand.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: brand.border),
              boxShadow: [
                BoxShadow(
                  color: brand.shadow,
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: iconBackground,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, size: 22, color: iconColor),
                ),
                const SizedBox(height: 14),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w900,
                    color: brand.ink,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: brand.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
