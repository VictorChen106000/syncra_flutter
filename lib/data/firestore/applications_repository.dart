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
        .orderBy('submitted_at', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(_fromDoc).toList());
  }

  Future<void> updateStatus(
    String uid,
    String applicationId,
    JobStatus status,
  ) async {
    await _paths.applications(uid).doc(applicationId).update({
      'status': status.name,
      'last_update_at': FieldValue.serverTimestamp(),
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
      'last_update_at': FieldValue.serverTimestamp(),
    });
  }

  Future<String> createApplication({
    required String uid,
    required Job job,
    required JobStatus status,
    String? nextStep,
  }) async {
    final ref = _paths.applications(uid).doc();
    final now = FieldValue.serverTimestamp();
    await ref.set({
      'job': _jobToMap(job),
      'status': status.name,
      'submitted_at': now,
      'last_update_at': now,
      'next_step': nextStep,
      'notes': <Map<String, dynamic>>[],
    });
    return ref.id;
  }
}

TrackedApplication _fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
  final data = doc.data();
  final job = _jobFromMap(Map<String, dynamic>.from(data['job'] as Map));
  final submittedAt = _toDate(data['submitted_at']);
  final lastUpdateAt = _toDate(data['last_update_at']);
  final notesRaw = (data['notes'] as List?) ?? const [];

  return TrackedApplication(
    id: doc.id,
    job: job,
    status: _statusFromName(data['status'] as String?),
    submittedLabel: _relativeLabel(submittedAt),
    lastUpdate: _relativeLabel(lastUpdateAt),
    nextStep: data['next_step'] as String?,
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

JobStatus _statusFromName(String? name) {
  for (final s in JobStatus.values) {
    if (s.name == name) return s;
  }
  return JobStatus.submitted;
}

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

String _relativeLabel(DateTime? when) {
  if (when == null) return 'Just now';
  final diff = DateTime.now().difference(when);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inDays < 1) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return '${(diff.inDays / 7).floor()}w ago';
}
