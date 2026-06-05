import 'dart:async';

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
class ChatHistoryDrawer extends ConsumerStatefulWidget {
  const ChatHistoryDrawer({super.key});

  @override
  ConsumerState<ChatHistoryDrawer> createState() => _ChatHistoryDrawerState();
}

class _ChatHistoryDrawerState extends ConsumerState<ChatHistoryDrawer> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_handleSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _handleSearchChanged() {
    final next = _searchController.text;
    if (next == _query) return;
    setState(() => _query = next);
  }

  @override
  Widget build(BuildContext context) {
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
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppConstants.screenHorizontalPadding,
                0,
                AppConstants.screenHorizontalPadding,
                12,
              ),
              child: _SearchField(
                controller: _searchController,
                hasQuery: _query.trim().isNotEmpty,
                onClear: () => _searchController.clear(),
              ),
            ),
            Expanded(
              child: convos.when(
                loading: () => const _LoadingState(),
                error: (_, _) => const _ErrorState(),
                data: (list) {
                  if (list.isEmpty) return const _EmptyState();
                  final filtered = _filterConversations(list, _query);
                  if (filtered.isEmpty) return const _SearchEmptyState();
                  final pinned = _pinnedConversations(filtered);
                  final groups = _groupConversationsByDate(
                    _unpinnedConversations(filtered),
                  );
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(
                      AppConstants.screenHorizontalPadding,
                      4,
                      AppConstants.screenHorizontalPadding,
                      40,
                    ),
                    children: [
                      if (pinned.isNotEmpty)
                        _ConversationSection(
                          group: _ConversationGroup(
                            label: 'Pinned',
                            conversations: pinned,
                          ),
                          currentId: currentId,
                          onOpen: (c) {
                            Navigator.of(context).maybePop();
                            notifier.switchConversation(c.id);
                          },
                          onRename: (c) =>
                              unawaited(_renameConversation(context, c)),
                          onTogglePinned: (c) => unawaited(
                            notifier.setConversationPinned(
                              c.id,
                              pinned: !c.pinned,
                            ),
                          ),
                          onDelete: (c) => _confirmDelete(context, c),
                        ),
                      for (final group in groups)
                        _ConversationSection(
                          group: group,
                          currentId: currentId,
                          onOpen: (c) {
                            Navigator.of(context).maybePop();
                            notifier.switchConversation(c.id);
                          },
                          onRename: (c) =>
                              unawaited(_renameConversation(context, c)),
                          onTogglePinned: (c) => unawaited(
                            notifier.setConversationPinned(
                              c.id,
                              pinned: !c.pinned,
                            ),
                          ),
                          onDelete: (c) => _confirmDelete(context, c),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
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

  Future<void> _renameConversation(
    BuildContext context,
    ConversationSummary c,
  ) async {
    final title = await _showRenameDialog(context, c);
    if (!mounted || title == null) return;
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty || cleanTitle == c.title.trim()) return;
    await ref
        .read(agentChatProvider.notifier)
        .renameConversation(c.id, cleanTitle);
  }

  Future<String?> _showRenameDialog(
    BuildContext context,
    ConversationSummary c,
  ) async {
    final controller = TextEditingController(text: c.title);
    var draft = c.title;
    try {
      return await showDialog<String>(
        context: context,
        builder: (ctx) {
          final brand = ctx.brand;
          return StatefulBuilder(
            builder: (ctx, setDialogState) {
              final canSave = draft.trim().isNotEmpty;
              return AlertDialog(
                backgroundColor: brand.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                ),
                title: Text(
                  'Rename chat',
                  style: TextStyle(
                    color: brand.ink,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                content: TextField(
                  controller: controller,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  maxLength: 80,
                  style: TextStyle(
                    color: brand.ink,
                    fontWeight: FontWeight.w700,
                  ),
                  cursorColor: brand.accent,
                  decoration: InputDecoration(
                    labelText: 'Chat title',
                    labelStyle: TextStyle(color: brand.textMuted),
                    filled: true,
                    fillColor: brand.surfaceMuted,
                    counterStyle: TextStyle(color: brand.textSoft),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: brand.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: brand.accent, width: 1.4),
                    ),
                  ),
                  onChanged: (value) => setDialogState(() => draft = value),
                  onSubmitted: (_) {
                    final cleanTitle = controller.text.trim();
                    if (cleanTitle.isNotEmpty) {
                      Navigator.of(ctx).pop(cleanTitle);
                    }
                  },
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: canSave
                        ? () => Navigator.of(ctx).pop(controller.text.trim())
                        : null,
                    child: const Text('Save'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      controller.dispose();
    }
  }
}

class _ConversationSection extends StatelessWidget {
  const _ConversationSection({
    required this.group,
    required this.currentId,
    required this.onOpen,
    required this.onRename,
    required this.onTogglePinned,
    required this.onDelete,
  });

  final _ConversationGroup group;
  final String currentId;
  final ValueChanged<ConversationSummary> onOpen;
  final ValueChanged<ConversationSummary> onRename;
  final ValueChanged<ConversationSummary> onTogglePinned;
  final ValueChanged<ConversationSummary> onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(label: group.label),
          const SizedBox(height: 8),
          for (var i = 0; i < group.conversations.length; i++)
            Padding(
              padding: EdgeInsets.only(
                bottom: i == group.conversations.length - 1 ? 0 : 8,
              ),
              child:
                  _ConversationRow(
                        summary: group.conversations[i],
                        active: group.conversations[i].id == currentId,
                        onTap: () => onOpen(group.conversations[i]),
                        onRename: () => onRename(group.conversations[i]),
                        onTogglePinned: () =>
                            onTogglePinned(group.conversations[i]),
                        onDelete: () => onDelete(group.conversations[i]),
                      )
                      .animate(delay: (i * 35).ms)
                      .fadeIn(duration: 220.ms)
                      .moveX(begin: -10, end: 0),
            ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 6),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: brand.textMuted,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                color: brand.border.withValues(alpha: brand.isDark ? 0.7 : 0.8),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConversationGroup {
  const _ConversationGroup({required this.label, required this.conversations});

  final String label;
  final List<ConversationSummary> conversations;
}

List<_ConversationGroup> _groupConversationsByDate(
  List<ConversationSummary> conversations,
) {
  final today = _dateOnly(DateTime.now());
  final buckets = <String, List<ConversationSummary>>{
    'Today': <ConversationSummary>[],
    'Yesterday': <ConversationSummary>[],
    'Previous 7 days': <ConversationSummary>[],
    'Older': <ConversationSummary>[],
  };

  for (final conversation in conversations) {
    final updatedAt = _dateOnly(conversation.updatedAt.toLocal());
    final dayDelta = today.difference(updatedAt).inDays;

    final label = dayDelta <= 0
        ? 'Today'
        : dayDelta == 1
        ? 'Yesterday'
        : dayDelta <= 7
        ? 'Previous 7 days'
        : 'Older';

    buckets[label]!.add(conversation);
  }

  return [
    for (final entry in buckets.entries)
      if (entry.value.isNotEmpty)
        _ConversationGroup(label: entry.key, conversations: entry.value),
  ];
}

DateTime _dateOnly(DateTime value) {
  return DateTime(value.year, value.month, value.day);
}

List<ConversationSummary> _filterConversations(
  List<ConversationSummary> conversations,
  String query,
) {
  final cleanQuery = query.trim().toLowerCase();
  if (cleanQuery.isEmpty) return conversations;

  return [
    for (final conversation in conversations)
      if (conversation.title.toLowerCase().contains(cleanQuery)) conversation,
  ];
}

List<ConversationSummary> _pinnedConversations(
  List<ConversationSummary> conversations,
) {
  return [
    for (final conversation in conversations)
      if (conversation.pinned) conversation,
  ];
}

List<ConversationSummary> _unpinnedConversations(
  List<ConversationSummary> conversations,
) {
  return [
    for (final conversation in conversations)
      if (!conversation.pinned) conversation,
  ];
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

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.hasQuery,
    required this.onClear,
  });

  final TextEditingController controller;
  final bool hasQuery;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Container(
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: brand.border),
        boxShadow: [
          BoxShadow(
            color: brand.shadow,
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        textInputAction: TextInputAction.search,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: brand.ink,
        ),
        cursorColor: brand.accent,
        decoration: InputDecoration(
          hintText: 'Search chats',
          hintStyle: TextStyle(
            color: brand.textSoft,
            fontWeight: FontWeight.w700,
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            size: 20,
            color: brand.textMuted,
          ),
          suffixIcon: hasQuery
              ? IconButton(
                  tooltip: 'Clear search',
                  onPressed: onClear,
                  icon: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: brand.textMuted,
                  ),
                )
              : null,
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 15),
        ),
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
    required this.onRename,
    required this.onTogglePinned,
    required this.onDelete,
  });

  final ConversationSummary summary;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onTogglePinned;
  final VoidCallback onDelete;

  @override
  State<_ConversationRow> createState() => _ConversationRowState();
}

class _ConversationRowState extends State<_ConversationRow> {
  bool _rowHovered = false;
  bool _menuHovered = false;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final active = widget.active;
    final rowRadius = BorderRadius.circular(18);
    final menuColor = _menuHovered
        ? brand.ink
        : brand.textSoft.withValues(alpha: brand.isDark ? 0.72 : 0.58);

    return MouseRegion(
      onEnter: (_) => setState(() => _rowHovered = true),
      onExit: (_) => setState(() {
        _rowHovered = false;
        _menuHovered = false;
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
                    onEnter: (_) => setState(() => _menuHovered = true),
                    onExit: (_) => setState(() => _menuHovered = false),
                    child: _ConversationActionsButton(
                      pinned: widget.summary.pinned,
                      color: menuColor,
                      onRename: widget.onRename,
                      onTogglePinned: widget.onTogglePinned,
                      onDelete: widget.onDelete,
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

class _ConversationActionsButton extends StatelessWidget {
  const _ConversationActionsButton({
    required this.pinned,
    required this.color,
    required this.onRename,
    required this.onTogglePinned,
    required this.onDelete,
  });

  final bool pinned;
  final Color color;
  final VoidCallback onRename;
  final VoidCallback onTogglePinned;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return PopupMenuButton<_ConversationAction>(
      tooltip: 'Chat actions',
      color: brand.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onSelected: (action) {
        switch (action) {
          case _ConversationAction.rename:
            onRename();
            return;
          case _ConversationAction.togglePinned:
            onTogglePinned();
            return;
          case _ConversationAction.delete:
            onDelete();
            return;
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _ConversationAction.rename,
          child: _ConversationMenuItem(
            icon: Icons.drive_file_rename_outline_rounded,
            label: 'Rename',
            color: brand.ink,
          ),
        ),
        PopupMenuItem(
          value: _ConversationAction.togglePinned,
          child: _ConversationMenuItem(
            icon: pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
            label: pinned ? 'Unpin' : 'Pin',
            color: brand.ink,
          ),
        ),
        PopupMenuItem(
          value: _ConversationAction.delete,
          child: _ConversationMenuItem(
            icon: Icons.delete_outline_rounded,
            label: 'Delete',
            color: brand.danger,
          ),
        ),
      ],
      child: SizedBox(
        width: 40,
        height: 40,
        child: Icon(Icons.more_horiz_rounded, size: 20, color: color),
      ),
    );
  }
}

class _ConversationMenuItem extends StatelessWidget {
  const _ConversationMenuItem({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(fontWeight: FontWeight.w700, color: color),
        ),
      ],
    );
  }
}

enum _ConversationAction { rename, togglePinned, delete }

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

class _SearchEmptyState extends StatelessWidget {
  const _SearchEmptyState();

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return _StatusCard(
      icon: Icons.search_off_rounded,
      iconColor: brand.textMuted,
      iconBackground: brand.surfaceMuted,
      title: 'No matching chats',
      message: 'Try another title or clear search to see all saved chats.',
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
