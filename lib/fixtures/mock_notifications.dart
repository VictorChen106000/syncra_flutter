enum NotificationKind { intercept, reply, drafted, undo, match }

class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.timestamp,
    this.unread = false,
    this.actionLabel,
  });

  final String id;
  final NotificationKind kind;
  final String title;
  final String body;
  final String timestamp;
  final bool unread;
  final String? actionLabel;
}

class MockNotifications {
  const MockNotifications._();

  static const List<AppNotification> all = [
    AppNotification(
      id: 'n0',
      kind: NotificationKind.intercept,
      title: 'Agent intercept',
      body: 'Binance updated their JD 10 min ago. Pausing submission until you review.',
      timestamp: 'Just now',
      unread: true,
      actionLabel: 'Review',
    ),
    AppNotification(
      id: 'n1',
      kind: NotificationKind.reply,
      title: 'TechFlow recruiter replied',
      body: 'They want to schedule a 30-min intro call. Draft response ready.',
      timestamp: '12m ago',
      unread: true,
      actionLabel: 'Open draft',
    ),
    AppNotification(
      id: 'n2',
      kind: NotificationKind.match,
      title: '3 new strong matches',
      body: 'Found 3 roles at 90%+ match overnight. Drafts queued for review.',
      timestamp: '1h ago',
      unread: true,
      actionLabel: 'See queue',
    ),
    AppNotification(
      id: 'n3',
      kind: NotificationKind.drafted,
      title: 'Cover letter ready',
      body: 'Tailored Linear cover letter is ready in your review queue.',
      timestamp: '3h ago',
    ),
    AppNotification(
      id: 'n4',
      kind: NotificationKind.undo,
      title: 'Auto-tailor applied',
      body: 'Resume v3 was auto-tailored for the Vercel role. You can undo within 24h.',
      timestamp: 'Yesterday',
      actionLabel: 'Undo',
    ),
  ];

  static int get unreadCount => all.where((n) => n.unread).length;
}
