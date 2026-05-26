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
      'name': firebaseUser.displayName ??
          (firebaseUser.email?.split('@').first ?? 'User'),
      'email': firebaseUser.email ?? '',
      'avatar_url': firebaseUser.photoURL,
      'role': null,
      'is_agent_active': true,
      'morning_brief_enabled': false,
      'gmail_connected': false,
      'has_completed_onboarding': false,
      'created_at': FieldValue.serverTimestamp(),
    });
  }

  Stream<Map<String, dynamic>?> watchUser(String uid) {
    return _paths.user(uid).snapshots().map((s) => s.data());
  }

  Stream<UserProfile?> watchProfile(String uid) {
    return _paths.user(uid).snapshots().map(
          (s) => s.data() == null ? null : UserProfile.fromMap(s.data()!),
        );
  }

  /// Partial update of `users/{uid}`. Pass only the fields you want to
  /// change; the others remain untouched (Firestore `update` semantics,
  /// not `set`).
  Future<void> update(
    String uid, {
    String? role,
    bool? isAgentActive,
    bool? morningBriefEnabled,
    bool? gmailConnected,
    bool? hasCompletedOnboarding,
    ResumeFit? resumeFit,
  }) async {
    final patch = <String, dynamic>{};
    if (role != null) patch['role'] = role;
    if (isAgentActive != null) patch['is_agent_active'] = isAgentActive;
    if (morningBriefEnabled != null) {
      patch['morning_brief_enabled'] = morningBriefEnabled;
    }
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

  /// Wipes every user-owned subcollection (applications, resumes, pipeline,
  /// briefs, conversations, learned_facts) and any associated Storage blobs.
  /// The auth account and the `users/{uid}` profile doc are left intact so
  /// the user remains signed in on a clean slate.
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
