import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/dev/dev_flags_notifier.dart';
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

/// Hard-coded preview entries for the notifications inbox UI. Surfaced only
/// when the developer toggle `showMockNotifications` is on — gives a
/// realistic feel for the bell + inbox while the agent backend is still in
/// flight. Order matches "newest first" rendering.
const List<AppNotification> _mockAgentActivity = [
  AppNotification(
    id: 'mock-intercept-1',
    kind: NotificationKind.intercept,
    title: 'Agent needs your input',
    body: 'Should I use your "Product-focused" resume for the Linear PM role?',
    timestamp: 'Just now',
    actionLabel: 'Answer',
  ),
  AppNotification(
    id: 'mock-drafted-1',
    kind: NotificationKind.drafted,
    title: 'Tailored resume ready',
    body: 'Drafted a resume for Vercel · Senior Product Engineer · 94% match.',
    timestamp: '4m ago',
    actionLabel: 'Review',
  ),
  AppNotification(
    id: 'mock-match-1',
    kind: NotificationKind.match,
    title: '3 strong matches this morning',
    body: 'Linear, Vercel and Anthropic surfaced overnight. Top match 94%.',
    timestamp: '12m ago',
    actionLabel: 'See pipeline',
  ),
  AppNotification(
    id: 'mock-undo-1',
    kind: NotificationKind.undo,
    title: 'Applied to Ramp',
    body: 'Submitted application to Ramp · Product Designer. Reversible for 5m.',
    timestamp: '28m ago',
    actionLabel: 'Undo',
  ),
  AppNotification(
    id: 'mock-reply-1',
    kind: NotificationKind.reply,
    title: 'Recruiter replied · Notion',
    body: '"Thanks for applying — we’d love to schedule a 30-min intro chat next week."',
    timestamp: '1h ago',
    unread: false,
    actionLabel: 'Open thread',
  ),
];

class NotificationsNotifier extends Notifier<NotificationsState> {
  int _seq = 0;

  @override
  NotificationsState build() {
    // Re-seed / clear mocks whenever the dev toggle flips. Listening inside
    // build is the standard Riverpod way to react to other providers without
    // leaking subscriptions.
    ref.listen<DevFlags>(devFlagsProvider, (prev, next) {
      if (prev?.showMockNotifications == next.showMockNotifications) return;
      if (next.showMockNotifications) {
        _seedMocks();
      } else {
        _clearMocks();
      }
    }, fireImmediately: true);
    return const NotificationsState();
  }

  void _seedMocks() {
    // Replace anything mock-prefixed but keep real agent-generated entries.
    final real = state.items.where((n) => !n.id.startsWith('mock-')).toList();
    state = state.copyWith(items: [..._mockAgentActivity, ...real]);
  }

  void _clearMocks() {
    final real = state.items.where((n) => !n.id.startsWith('mock-')).toList();
    if (real.length == state.items.length) return;
    state = state.copyWith(items: real);
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
