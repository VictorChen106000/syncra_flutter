import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../features/auth/models/user_profile.dart';
import '../../features/resumes/models/resume_fit.dart';
import 'firestore_paths.dart';

class UserRepository {
  UserRepository({FirebaseFirestore? db, FirebaseStorage? storage})
    : _paths = FirestorePaths(db ?? FirebaseFirestore.instance),
      _storage = storage ?? FirebaseStorage.instance;

  final FirestorePaths _paths;
  final FirebaseStorage _storage;

  Future<void> ensureUserDoc(User firebaseUser) async {
    final ref = _paths.user(firebaseUser.uid);
    final snap = await ref.get();
    if (snap.exists) return;

    await ref.set({
      'name':
          firebaseUser.displayName ??
          (firebaseUser.email?.split('@').first ?? 'User'),
      'email': firebaseUser.email ?? '',
      'avatar_url': firebaseUser.photoURL,
      'role': null,
      'is_agent_active': true,
      'gmail_connected': false,
      'has_completed_onboarding': false,
      'created_at': FieldValue.serverTimestamp(),
    });
  }

  Stream<Map<String, dynamic>?> watchUser(String uid) {
    return _paths.user(uid).snapshots().map((s) => s.data());
  }

  Stream<UserProfile?> watchProfile(String uid) {
    return _paths
        .user(uid)
        .snapshots()
        .map((s) => s.data() == null ? null : UserProfile.fromMap(s.data()!));
  }

  /// Partial update of `users/{uid}`. Pass only the fields you want to
  /// change; the others remain untouched (Firestore `update` semantics,
  /// not `set`).
  Future<void> update(
    String uid, {
    String? role,
    bool? isAgentActive,
    bool? gmailConnected,
    bool? hasCompletedOnboarding,
    ResumeFit? resumeFit,
  }) async {
    final patch = <String, dynamic>{};
    if (role != null) patch['role'] = role;
    if (isAgentActive != null) patch['is_agent_active'] = isAgentActive;
    if (gmailConnected != null) patch['gmail_connected'] = gmailConnected;
    if (hasCompletedOnboarding != null) {
      patch['has_completed_onboarding'] = hasCompletedOnboarding;
    }
    if (resumeFit != null) patch['resume_fit'] = resumeFit.toJson();
    if (patch.isEmpty) return;
    await _paths.user(uid).update(patch);
  }

  /// Best-effort delete of the user's Firestore document. Sub-collections
  /// (applications/resumes/etc.) are owned by the user via security rules
  /// and will be orphaned until manually cleaned; that's acceptable for v1.
  Future<void> deleteUserDoc(String uid) async {
    await _paths.user(uid).delete();
  }

  /// Updates one learned Career Memory fact after the user edits it.
  /// Resumes, pipeline cards, applications, briefs, and conversations are
  /// left untouched.
  Future<void> updateLearnedFact(
    String uid,
    String factId, {
    required String topic,
    required String detail,
    required String category,
  }) {
    final cleanId = factId.trim();
    final cleanTopic = topic.trim();
    final cleanDetail = detail.trim();
    final cleanCategory = category.trim().isEmpty ? 'other' : category.trim();

    if (cleanId.isEmpty || cleanTopic.isEmpty || cleanDetail.isEmpty) {
      return Future.value();
    }

    return _paths.learnedFacts(uid).doc(cleanId).update({
      'topic': cleanTopic,
      'detail': cleanDetail,
      'category': cleanCategory,
      'source': 'user',
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  /// Deletes one learned Career Memory fact. Resumes, pipeline cards,
  /// applications, briefs, and conversations are left untouched.
  Future<void> deleteLearnedFact(String uid, String factId) {
    final cleanId = factId.trim();
    if (cleanId.isEmpty) return Future.value();
    return _paths.learnedFacts(uid).doc(cleanId).delete();
  }

  /// Deletes only the agent's learned Career Memory facts. Resumes, pipeline
  /// cards, applications, briefs, and conversations are left untouched.
  Future<void> clearLearnedFacts(String uid) {
    return _deleteCollection(_paths.learnedFacts(uid));
  }

  /// Wipes every user-owned subcollection (applications, resumes, pipeline,
  /// briefs, conversations, learned_facts) and any associated Storage blobs,
  /// then rolls the `users/{uid}` profile doc back to its first-run shape so
  /// the router drops the user into onboarding again — a true "start over".
  /// The Firebase auth account is kept (the user stays signed in) and identity
  /// fields (name / email / avatar / created_at) are preserved; everything the
  /// user configured (role, agent toggles, resume-fit, onboarding flag) resets.
  Future<void> resetUserData(String uid) async {
    final resumesSnap = await _paths.resumes(uid).get();
    for (final doc in resumesSnap.docs) {
      final path = doc.data()['storage_path'] as String?;
      if (path == null || path.isEmpty) continue;
      try {
        await _storage.ref(path).delete();
      } catch (_) {
        // Best-effort. A leaked blob is harmless; the Firestore doc is gone.
      }
    }

    await Future.wait([
      _deleteCollection(_paths.resumes(uid)),
      _deleteCollection(_paths.applications(uid)),
      _deleteCollection(_paths.pipeline(uid)),
      _deleteCollection(_paths.briefs(uid)),
      _deleteCollection(_paths.conversations(uid)),
      _deleteCollection(_paths.learnedFacts(uid)),
    ]);

    // Flip the profile doc back to first-run. `has_completed_onboarding: false`
    // is what the router redirect keys off to bounce the user to onboarding.
    await _paths.user(uid).update({
      'role': null,
      'is_agent_active': true,
      'gmail_connected': false,
      'has_completed_onboarding': false,
      'resume_fit': FieldValue.delete(),
    });
  }

  Future<void> _deleteCollection(
    CollectionReference<Map<String, dynamic>> col,
  ) async {
    final snap = await col.get();
    for (final doc in snap.docs) {
      await doc.reference.delete();
    }
  }
}
