import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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
      'autonomy_level': 'suggest',
      'created_at': FieldValue.serverTimestamp(),
    });
  }

  Stream<Map<String, dynamic>?> watchUser(String uid) {
    return _paths.user(uid).snapshots().map((s) => s.data());
  }
}
