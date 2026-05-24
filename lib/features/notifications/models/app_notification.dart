import 'package:flutter/foundation.dart';

enum NotificationKind {
  /// Agent paused mid-loop and needs information from the user (ask_user).
  intercept,

  /// Agent surfaced a concrete action (e.g. "Send to Linear", "Save tailored
  /// resume") that needs Accept/Make-changes from the user. The matching
  /// chat block is referenced via [AppNotification.targetBlockId] so the
  /// notification banner can settle the proposal without opening the chat.
  proposal,

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
    this.secondaryActionLabel,
    this.targetBlockId,
  });

  final String id;
  final NotificationKind kind;
  final String title;
  final String body;

  /// Human-friendly relative time ("Just now", "12m ago"). Computed by the
  /// caller — the notifier doesn't update this on its own.
  final String timestamp;
  final bool unread;

  /// Label for the primary action (e.g. "Accept", "Open chat", "Answer").
  final String? actionLabel;

  /// Label for an optional secondary action — used by [NotificationKind.proposal]
  /// to expose "Make changes" alongside the primary "Accept" so the user can
  /// dispatch the proposal straight from the banner.
  final String? secondaryActionLabel;

  /// Id of the agent-chat block this notification refers to. Lets the banner
  /// / inbox row route Accept / Make-changes back to the right
  /// `ActionProposalBlock` or `InputRequestBlock` without re-deriving it.
  final String? targetBlockId;

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
      secondaryActionLabel: secondaryActionLabel,
      targetBlockId: targetBlockId,
    );
  }
}
