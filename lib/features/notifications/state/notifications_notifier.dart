import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../fixtures/mock_notifications.dart';

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
  @override
  NotificationsState build() {
    return NotificationsState(items: List.of(MockNotifications.all));
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
    next[idx] = _copyWith(next[idx], unread: false);
    state = state.copyWith(items: next);
  }

  void markAllRead() {
    var changed = false;
    final next = [...state.items];
    for (var i = 0; i < next.length; i++) {
      if (next[i].unread) {
        next[i] = _copyWith(next[i], unread: false);
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

  AppNotification _copyWith(AppNotification n, {required bool unread}) {
    return AppNotification(
      id: n.id,
      kind: n.kind,
      title: n.title,
      body: n.body,
      timestamp: n.timestamp,
      actionLabel: n.actionLabel,
      unread: unread,
    );
  }
}

final notificationsProvider =
    NotifierProvider<NotificationsNotifier, NotificationsState>(NotificationsNotifier.new);
