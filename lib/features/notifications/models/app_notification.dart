import 'package:flutter/foundation.dart';

import '../../agent_chat/models/agent_block.dart';
import '../../agent_chat/services/agent_service.dart';

enum NotificationKind {
  /// Agent paused mid-loop and needs information from the user (ask_user).
  intercept,

  /// A recruiter reply came in (Gmail watcher, post-v1).
  reply,

  /// A draft (resume / cover letter / application) is ready to review.
  drafted,

  /// Action was applied but is reversible — surfaces an Undo affordance.
  undo,

  /// Pipeline scan found strong matches.
  match,
}

@immutable
class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.timestamp,
    this.unread = true,
    this.actionLabel,
  });

  final String id;
  final NotificationKind kind;
  final String title;
  final String body;

  /// Human-friendly relative time ("Just now", "12m ago"). Computed by the
  /// caller — the notifier doesn't update this on its own.
  final String timestamp;
  final bool unread;
  final String? actionLabel;

  AppNotification copyWith({
    bool? unread,
    String? timestamp,
  }) {
    return AppNotification(
      id: id,
      kind: kind,
      title: title,
      body: body,
      timestamp: timestamp ?? this.timestamp,
      unread: unread ?? this.unread,
      actionLabel: actionLabel,
    );
  }

  /// Maps an [AgentEvent] to an inbox entry. Returns null when the event
  /// doesn't warrant a notification (e.g. plain ThinkingBlock additions).
  static AppNotification? fromAgentEvent(
    AgentEvent event, {
    required String idSeed,
  }) {
    return switch (event) {
      BlockAdded(:final block) when block is InputRequestBlock =>
        AppNotification(
          id: idSeed,
          kind: NotificationKind.intercept,
          title: 'Agent needs your input',
          body: block.question,
          timestamp: 'Just now',
          actionLabel: 'Answer',
        ),
      ToolCallCompleted(:final summary, :final status)
          when status == ToolCallStatus.done && summary.isNotEmpty =>
        AppNotification(
          id: idSeed,
          kind: NotificationKind.drafted,
          title: 'Agent finished a task',
          body: summary,
          timestamp: 'Just now',
          actionLabel: 'Open chat',
        ),
      _ => null,
    };
  }
}
