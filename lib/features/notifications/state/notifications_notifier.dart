import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../agent_chat/models/agent_block.dart';
import '../../agent_chat/services/agent_service.dart';
import '../models/app_notification.dart';

enum NotificationsFilter { all, unread }

@immutable
class NotificationsState {
  const NotificationsState({
    this.items = const [],
    this.filter = NotificationsFilter.all,
    this.lastMessage,
  });

  final List<AppNotification> items;
  final NotificationsFilter filter;
  final String? lastMessage;

  int get unreadCount => items.where((n) => n.unread).length;

  List<AppNotification> get filtered {
    if (filter == NotificationsFilter.unread) {
      return items.where((n) => n.unread).toList();
    }
    return items;
  }

  NotificationsState copyWith({
    List<AppNotification>? items,
    NotificationsFilter? filter,
    String? lastMessage,
    bool clearMessage = false,
  }) {
    return NotificationsState(
      items: items ?? this.items,
      filter: filter ?? this.filter,
      lastMessage: clearMessage ? null : (lastMessage ?? this.lastMessage),
    );
  }
}

/// The inbox of agent activity. The agent-chat layer is the primary producer:
/// when a turn yields a block worth surfacing (intercept, proposal, finished
/// tool call) it calls [add] with a fully-formed [AppNotification]. Producers
/// that don't have tool-level context (the passive morning-brief agent) use
/// [onAgentEvent] for generic copy.
class NotificationsNotifier extends Notifier<NotificationsState> {
  int _seq = 0;

  @override
  NotificationsState build() => const NotificationsState();

  /// Pushes a new entry to the top of the inbox. Dedupes on [AppNotification.id]
  /// so callers can safely re-emit the same notification (e.g. a proposal that
  /// rebuilds) without piling duplicates into the list.
  void add(AppNotification entry) {
    final existingIdx = state.items.indexWhere((n) => n.id == entry.id);
    if (existingIdx == -1) {
      state = state.copyWith(items: [entry, ...state.items]);
      return;
    }
    final next = [...state.items]..[existingIdx] = entry;
    state = state.copyWith(items: next);
  }

  /// Convenience entry point for producers that only have raw [AgentEvent]s —
  /// most notably the passive morning-brief loop. Generates generic inbox
  /// copy; the chat layer, which can see tool labels, builds richer entries
  /// via [add] directly.
  void onAgentEvent(AgentEvent event) {
    AppNotification? entry;
    switch (event) {
      case BlockAdded(:final block) when block is InputRequestBlock:
        entry = AppNotification(
          id: 'n${_seq++}',
          kind: NotificationKind.intercept,
          title: 'Agent needs your input',
          body: block.question,
          timestamp: 'Just now',
          actionLabel: 'Answer',
          targetBlockId: block.id,
        );
      case ToolCallCompleted(:final summary, :final status)
          when status == ToolCallStatus.done && summary.isNotEmpty:
        entry = AppNotification(
          id: 'n${_seq++}',
          kind: NotificationKind.drafted,
          title: 'Agent finished a task',
          body: summary,
          timestamp: 'Just now',
          actionLabel: 'Open chat',
        );
      case _:
        return;
    }
    add(entry);
  }

  String? consumeMessage() {
    final m = state.lastMessage;
    if (m != null) {
      state = state.copyWith(clearMessage: true);
    }
    return m;
  }

  void setFilter(NotificationsFilter f) {
    if (f == state.filter) return;
    state = state.copyWith(filter: f);
  }

  void markRead(String id) {
    final idx = state.items.indexWhere((n) => n.id == id);
    if (idx == -1 || !state.items[idx].unread) return;
    final next = [...state.items];
    next[idx] = next[idx].copyWith(unread: false);
    state = state.copyWith(items: next);
  }

  /// Marks read every entry whose [AppNotification.targetBlockId] matches
  /// [blockId]. Used when the chat layer settles a proposal / ask_user block
  /// from its own UI, so the matching banner/inbox row clears in sync.
  void markReadByTargetBlock(String blockId) {
    var changed = false;
    final next = [...state.items];
    for (var i = 0; i < next.length; i++) {
      if (next[i].targetBlockId == blockId && next[i].unread) {
        next[i] = next[i].copyWith(unread: false);
        changed = true;
      }
    }
    if (changed) state = state.copyWith(items: next);
  }

  void markAllRead() {
    var changed = false;
    final next = [...state.items];
    for (var i = 0; i < next.length; i++) {
      if (next[i].unread) {
        next[i] = next[i].copyWith(unread: false);
        changed = true;
      }
    }
    if (changed) {
      state = state.copyWith(
        items: next,
        lastMessage: 'All notifications marked read',
      );
    }
  }
}

final notificationsProvider =
    NotifierProvider<NotificationsNotifier, NotificationsState>(NotificationsNotifier.new);
