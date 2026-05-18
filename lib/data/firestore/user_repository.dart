import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../features/auth/models/user_profile.dart';
import 'firestore_paths.dart';

class UserRepository {
  UserRepository({FirebaseFirestore? db})
      : _paths = FirestorePaths(db ?? FirebaseFirestore.instance);

  final FirestorePaths _paths;

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
      'autonomy_level': 'ask_first',
      'morning_brief_enabled': false,
      'gmail_connected': false,
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
    AutonomyLevel? autonomyLevel,
    bool? morningBriefEnabled,
    bool? gmailConnected,
  }) async {
    final patch = <String, dynamic>{};
    if (role != null) patch['role'] = role;
    if (isAgentActive != null) patch['is_agent_active'] = isAgentActive;
    if (autonomyLevel != null) patch['autonomy_level'] = autonomyLevel.wire;
    if (morningBriefEnabled != null) {
      patch['morning_brief_enabled'] = morningBriefEnabled;
    }
    if (gmailConnected != null) patch['gmail_connected'] = gmailConnected;
    if (patch.isEmpty) return;
    await _paths.user(uid).update(patch);
  }

  /// Best-effort delete of the user's Firestore document. Sub-collections
  /// (applications/resumes/etc.) are owned by the user via security rules
  /// and will be orphaned until manually cleaned; that's acceptable for v1.
  Future<void> deleteUserDoc(String uid) async {
    await _paths.user(uid).delete();
  }
}
