import 'package:flutter/foundation.dart';

import '../../../fixtures/mock_notifications.dart';

enum NotificationsFilter { all, unread }

class NotificationsController extends ChangeNotifier {
  NotificationsController() : _items = List.of(MockNotifications.all);

  final List<AppNotification> _items;
  NotificationsFilter _filter = NotificationsFilter.all;
  String? _lastMessage;

  NotificationsFilter get filter => _filter;
  List<AppNotification> get items => List.unmodifiable(_items);
  int get unreadCount => _items.where((n) => n.unread).length;

  List<AppNotification> get filtered {
    if (_filter == NotificationsFilter.unread) {
      return _items.where((n) => n.unread).toList();
    }
    return List.unmodifiable(_items);
  }

  String? consumeMessage() {
    final m = _lastMessage;
    _lastMessage = null;
    return m;
  }

  void setFilter(NotificationsFilter f) {
    _filter = f;
    notifyListeners();
  }

  void markRead(String id) {
    final idx = _items.indexWhere((n) => n.id == id);
    if (idx == -1 || !_items[idx].unread) return;
    _items[idx] = _copyWith(_items[idx], unread: false);
    notifyListeners();
  }

  void markAllRead() {
    var changed = false;
    for (var i = 0; i < _items.length; i++) {
      if (_items[i].unread) {
        _items[i] = _copyWith(_items[i], unread: false);
        changed = true;
      }
    }
    if (changed) {
      _lastMessage = 'All notifications marked read';
      notifyListeners();
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
