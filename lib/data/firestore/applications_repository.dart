import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/job.dart';
import '../models/tracked_application.dart';
import 'firestore_paths.dart';

class ApplicationsRepository {
  ApplicationsRepository({FirebaseFirestore? db})
    : _paths = FirestorePaths(db ?? FirebaseFirestore.instance);

  final FirestorePaths _paths;

  Stream<List<TrackedApplication>> watchApplications(String uid) {
    return _paths
        .applications(uid)
        .orderBy('drafted_at', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(_fromDoc).toList());
  }

  /// Agent creates a draft application. `sentAt` is null — the user must
  /// tap Send to mark it as actually submitted.
  Future<String> createApplication({
    required String uid,
    required Job job,
    String? resumeId,
    String trustRiskLevel = 'unchecked',
    String trustRiskLabel = 'Not checked',
    int trustSignalsCount = 0,
    List<Map<String, String>> trustSignals = const [],
    String trustSafeNextStep = '',
  }) async {
    final ref = _paths.applications(uid).doc();
    await ref.set({
      'job': _jobToMap(job),
      'resume_id': resumeId,
      'drafted_at': FieldValue.serverTimestamp(),
      'sent_at': null,
      'got_reply': false,
      'follow_up_at': null,
      'sent_email_id': null,
      'trust_risk_level': trustRiskLevel,
      'trust_risk_label': trustRiskLabel,
      'trust_signals_count': trustSignalsCount,
      'trust_signals': trustSignals,
      'trust_safe_next_step': trustSafeNextStep,
      'trust_checked_at': trustRiskLevel == 'unchecked'
          ? null
          : FieldValue.serverTimestamp(),
      'notes': <Map<String, dynamic>>[],
    });
    return ref.id;
  }

  /// User tapped Send (or the agent's `send_email` tool succeeded). Stamps
  /// `sent_at` and optionally records the Gmail message id.
  Future<void> markSent(
    String uid,
    String applicationId, {
    String? sentEmailId,
  }) async {
    await _paths.applications(uid).doc(applicationId).update({
      'sent_at': FieldValue.serverTimestamp(),
      'sent_email_id': ?sentEmailId,
    });
  }

  Future<void> setGotReply(
    String uid,
    String applicationId,
    bool gotReply,
  ) async {
    await _paths.applications(uid).doc(applicationId).update({
      'got_reply': gotReply,
    });
  }

  Future<void> setFollowUp(
    String uid,
    String applicationId,
    DateTime? followUpAt,
  ) async {
    await _paths.applications(uid).doc(applicationId).update({
      'follow_up_at': followUpAt == null
          ? null
          : Timestamp.fromDate(followUpAt),
    });
  }

  Future<void> addNote(String uid, String applicationId, String body) async {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return;

    await _paths.applications(uid).doc(applicationId).update({
      'notes': FieldValue.arrayUnion([
        {
          'id': 'note_${DateTime.now().microsecondsSinceEpoch}',
          'body': trimmed,
          'created_at': Timestamp.now(),
        },
      ]),
    });
  }

  Future<void> updateNote(
    String uid,
    String applicationId,
    List<TrackedApplicationNote> currentNotes,
    String noteId,
    String body,
  ) async {
    final cleanId = noteId.trim();
    final trimmed = body.trim();
    if (cleanId.isEmpty || trimmed.isEmpty) return;

    final next = currentNotes
        .map((note) => note.id == cleanId ? note.copyWith(body: trimmed) : note)
        .map(_noteToMap)
        .toList(growable: false);

    await _paths.applications(uid).doc(applicationId).update({'notes': next});
  }

  Future<void> deleteNote(
    String uid,
    String applicationId,
    List<TrackedApplicationNote> currentNotes,
    String noteId,
  ) async {
    final cleanId = noteId.trim();
    if (cleanId.isEmpty) return;

    final next = currentNotes
        .where((note) => note.id != cleanId)
        .map(_noteToMap)
        .toList(growable: false);

    await _paths.applications(uid).doc(applicationId).update({'notes': next});
  }

  Future<void> setTrustGuard(
    String uid,
    String applicationId, {
    required String trustRiskLevel,
    required String trustRiskLabel,
    required int trustSignalsCount,
    required List<Map<String, String>> trustSignals,
    required String trustSafeNextStep,
  }) async {
    await _paths.applications(uid).doc(applicationId).update({
      'trust_risk_level': trustRiskLevel,
      'trust_risk_label': trustRiskLabel,
      'trust_signals_count': trustSignalsCount,
      'trust_signals': trustSignals,
      'trust_safe_next_step': trustSafeNextStep,
      'trust_checked_at': trustRiskLevel == 'unchecked'
          ? null
          : FieldValue.serverTimestamp(),
    });
  }
}

TrackedApplication _fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
  final data = doc.data();
  final job = _jobFromMap(Map<String, dynamic>.from(data['job'] as Map));

  return TrackedApplication(
    id: doc.id,
    job: job,
    resumeId: data['resume_id'] as String?,
    draftedAt: _toDate(data['drafted_at']) ?? DateTime.now(),
    sentAt: _toDate(data['sent_at']),
    gotReply: (data['got_reply'] as bool?) ?? false,
    followUpAt: _toDate(data['follow_up_at']),
    sentEmailId: data['sent_email_id'] as String?,
    trustRiskLevel: (data['trust_risk_level'] as String?) ?? 'unchecked',
    trustRiskLabel: (data['trust_risk_label'] as String?) ?? 'Not checked',
    trustSignalsCount: (data['trust_signals_count'] as num?)?.toInt() ?? 0,
    trustSignals: _trustSignalsFrom(data['trust_signals']),
    trustSafeNextStep: (data['trust_safe_next_step'] as String?) ?? '',
    notes: _notesFrom(data['notes']),
  );
}

List<Map<String, String>> _trustSignalsFrom(Object? value) {
  if (value is! List) return const [];

  final signals = <Map<String, String>>[];

  for (final raw in value.whereType<Map>()) {
    final severity = raw['severity']?.toString().trim() ?? '';
    final label = raw['label']?.toString().trim() ?? '';
    final detail = raw['detail']?.toString().trim() ?? '';

    if (label.isEmpty && detail.isEmpty) continue;

    signals.add({
      'severity': severity.isEmpty ? 'medium' : severity,
      'label': label.isEmpty ? 'Trust signal' : label,
      'detail': detail,
    });
  }

  return signals;
}

Job _jobFromMap(Map<String, dynamic> m) => Job(
  id: (m['id'] ?? '').toString(),
  title: (m['title'] as String?) ?? '',
  company: (m['company'] as String?) ?? '',
  location: (m['location'] as String?) ?? '',
  salary: (m['salary'] as String?) ?? '',
  category: _categoryFromName(m['category'] as String?),
  matchScore: (m['match_score'] as num?)?.toInt() ?? 0,
  agentAction: (m['agent_action'] as String?) ?? '',
  agentJustification: (m['agent_justification'] as String?) ?? '',
  skills: List<String>.from((m['skills'] as List?) ?? const []),
  missingSkills: List<String>.from((m['missing_skills'] as List?) ?? const []),
  why: (m['why'] as String?) ?? '',
);

Map<String, dynamic> _jobToMap(Job j) => {
  'id': j.id,
  'title': j.title,
  'company': j.company,
  'location': j.location,
  'salary': j.salary,
  'category': j.category.name,
  'match_score': j.matchScore,
  'agent_action': j.agentAction,
  'agent_justification': j.agentJustification,
  'skills': j.skills,
  'missing_skills': j.missingSkills,
  'why': j.why,
};

JobCategory _categoryFromName(String? name) {
  for (final c in JobCategory.values) {
    if (c.name == name) return c;
  }
  return JobCategory.ready;
}

List<TrackedApplicationNote> _notesFrom(Object? value) {
  if (value is! List) return const [];

  final notes = <TrackedApplicationNote>[];

  for (var i = 0; i < value.length; i++) {
    final raw = value[i];
    if (raw is! Map) continue;

    final createdAt = _toDate(raw['created_at']) ?? DateTime.now();
    final rawId = raw['id']?.toString().trim() ?? '';

    notes.add(
      TrackedApplicationNote(
        id: rawId.isEmpty
            ? 'legacy_${createdAt.millisecondsSinceEpoch}_$i'
            : rawId,
        body: raw['body']?.toString() ?? '',
        createdAt: createdAt,
      ),
    );
  }

  return notes;
}

Map<String, dynamic> _noteToMap(TrackedApplicationNote note) => {
  'id': note.id,
  'body': note.body,
  'created_at': Timestamp.fromDate(note.createdAt),
};

DateTime? _toDate(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return null;
}
