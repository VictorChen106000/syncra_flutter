import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

class NotificationsNotifier extends Notifier<NotificationsState> {
  int _seq = 0;

  @override
  NotificationsState build() {
    return const NotificationsState();
  }

  /// Public entry point for the agent layer. Translates an [AgentEvent] into
  /// an inbox entry; no-ops when the event isn't user-visible (thinking
  /// blocks, plain text, etc.).
  ///
  /// Per v1 spec the inbox is a complete log of agent activity. A future
  /// refinement (track D coordination) can suppress entries when the chat
  /// page is the active route — but for the demo, always recording keeps
  /// the bell badge meaningful.
  void onAgentEvent(AgentEvent event) {
    final entry = AppNotification.fromAgentEvent(
      event,
      idSeed: 'n${_seq++}',
    );
    if (entry == null) return;
    state = state.copyWith(items: [entry, ...state.items]);
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
