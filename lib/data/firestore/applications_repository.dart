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
      if (sentEmailId != null) 'sent_email_id': sentEmailId,
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
      'follow_up_at':
          followUpAt == null ? null : Timestamp.fromDate(followUpAt),
    });
  }

  Future<void> addNote(String uid, String applicationId, String body) async {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return;
    await _paths.applications(uid).doc(applicationId).update({
      'notes': FieldValue.arrayUnion([
        {
          'body': trimmed,
          'created_at': Timestamp.now(),
        }
      ]),
    });
  }
}

TrackedApplication _fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
  final data = doc.data();
  final job = _jobFromMap(Map<String, dynamic>.from(data['job'] as Map));
  final notesRaw = (data['notes'] as List?) ?? const [];

  return TrackedApplication(
    id: doc.id,
    job: job,
    resumeId: data['resume_id'] as String?,
    draftedAt: _toDate(data['drafted_at']) ?? DateTime.now(),
    sentAt: _toDate(data['sent_at']),
    gotReply: (data['got_reply'] as bool?) ?? false,
    followUpAt: _toDate(data['follow_up_at']),
    sentEmailId: data['sent_email_id'] as String?,
    notes: notesRaw
        .whereType<Map>()
        .map((m) => TrackedApplicationNote(
              body: (m['body'] as String?) ?? '',
              createdAt: _toDate(m['created_at']) ?? DateTime.now(),
            ))
        .toList(growable: false),
  );
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
      missingSkills:
          List<String>.from((m['missing_skills'] as List?) ?? const []),
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

DateTime? _toDate(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return null;
}
