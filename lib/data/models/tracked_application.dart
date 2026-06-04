import 'package:flutter/foundation.dart';

import 'job.dart';

/// What stage an application is at, derived from timestamps + the user's
/// `gotReply` flag. The application data model is documented in
/// `docs/ARCHITECTURE.md`.
enum ApplicationPhase {
  /// Agent has prepared a draft. User hasn't sent it yet.
  draft,

  /// User tapped Send. Still waiting on the recruiter.
  sent,

  /// User manually marked "got a reply" — could be a real reply or just a
  /// view/auto-ack, the user decides.
  replied;

  String get label => switch (this) {
    ApplicationPhase.draft => 'Draft',
    ApplicationPhase.sent => 'Sent',
    ApplicationPhase.replied => 'Replied',
  };
}

@immutable
class TrackedApplicationNote {
  const TrackedApplicationNote({required this.body, required this.createdAt});

  final String body;
  final DateTime createdAt;
}

/// Activity-log entry in `users/{uid}/applications/{appId}` (v1.2 schema).
///
/// The old 5-stage `status` enum was dropped — we have no inbox read scope,
/// so `viewed`/`interview`/etc. were always wishful. Now: drafted, sent, and
/// a manual `gotReply` toggle the user flips themselves.
@immutable
class TrackedApplication {
  const TrackedApplication({
    required this.id,
    required this.job,
    required this.draftedAt,
    this.resumeId,
    this.sentAt,
    this.gotReply = false,
    this.followUpAt,
    this.sentEmailId,
    this.notes = const [],
    this.trustRiskLevel = 'unchecked',
    this.trustRiskLabel = 'Not checked',
    this.trustSignalsCount = 0,
    this.trustSignals = const [],
    this.trustSafeNextStep = '',
  });

  final String id;
  final Job job;
  final String? resumeId;
  final DateTime draftedAt;
  final DateTime? sentAt;
  final bool gotReply;
  final DateTime? followUpAt;
  final String? sentEmailId;
  final List<TrackedApplicationNote> notes;

  final String trustRiskLevel;
  final String trustRiskLabel;
  final int trustSignalsCount;
  final List<Map<String, String>> trustSignals;
  final String trustSafeNextStep;

  bool get needsTrustReview =>
      trustRiskLevel == 'medium' || trustRiskLevel == 'high';

  ApplicationPhase get phase {
    if (gotReply) return ApplicationPhase.replied;
    if (sentAt != null) return ApplicationPhase.sent;
    return ApplicationPhase.draft;
  }

  /// Timestamp used to sort the activity feed — the most recent meaningful
  /// event for this entry.
  DateTime get sortAt => sentAt ?? draftedAt;

  TrackedApplication copyWith({
    String? resumeId,
    DateTime? draftedAt,
    DateTime? sentAt,
    bool? gotReply,
    DateTime? followUpAt,
    String? sentEmailId,
    List<TrackedApplicationNote>? notes,
    String? trustRiskLevel,
    String? trustRiskLabel,
    int? trustSignalsCount,
    List<Map<String, String>>? trustSignals,
    String? trustSafeNextStep,
    bool clearSentAt = false,
    bool clearFollowUpAt = false,
  }) {
    return TrackedApplication(
      id: id,
      job: job,
      resumeId: resumeId ?? this.resumeId,
      draftedAt: draftedAt ?? this.draftedAt,
      sentAt: clearSentAt ? null : (sentAt ?? this.sentAt),
      gotReply: gotReply ?? this.gotReply,
      followUpAt: clearFollowUpAt ? null : (followUpAt ?? this.followUpAt),
      sentEmailId: sentEmailId ?? this.sentEmailId,
      notes: notes ?? this.notes,
      trustRiskLevel: trustRiskLevel ?? this.trustRiskLevel,
      trustRiskLabel: trustRiskLabel ?? this.trustRiskLabel,
      trustSignalsCount: trustSignalsCount ?? this.trustSignalsCount,
      trustSignals: trustSignals ?? this.trustSignals,
      trustSafeNextStep: trustSafeNextStep ?? this.trustSafeNextStep,
    );
  }
}
