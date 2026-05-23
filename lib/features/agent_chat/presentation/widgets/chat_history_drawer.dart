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
    final currentId =
        ref.watch(agentChatProvider.select((s) => s.conversationId));
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
                loading: () => const Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
                error: (_, _) => const _EmptyState(),
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
        16,
        AppConstants.screenHorizontalPadding,
        14,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Chats',
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
                  'Your conversation history',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
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
              shape: const CircleBorder(),
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
    return Material(
      color: brand.ink,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: 50,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_rounded, size: 18, color: brand.inkInverse),
              const SizedBox(width: 8),
              Text(
                'New chat',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: brand.inkInverse,
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
      color: brand.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: active ? brand.ink : brand.border,
              width: active ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: active ? brand.ink : brand.surfaceMuted,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.chat_bubble_outline_rounded,
                  size: 16,
                  color: active ? brand.accent : brand.textMuted,
                ),
              ),
              const SizedBox(width: 12),
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
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: brand.ink,
                        letterSpacing: -0.15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      DateFormatter.relativeShort(summary.updatedAt),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
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
                    width: 44,
                    height: 44,
                    child: Icon(
                      Icons.delete_outline_rounded,
                      size: 18,
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

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
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
              Icon(Icons.forum_outlined, size: 28, color: brand.textMuted),
              const SizedBox(height: 10),
              Text(
                'No chats yet',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: brand.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Your conversations with Syncra will show up here.',
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
