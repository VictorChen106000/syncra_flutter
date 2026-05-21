import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../email/services/gmail_service.dart';
import '../models/app_user.dart';

/// Wraps Google Sign-In and FirebaseAuth into a single service.
class GoogleAuthService {
  GoogleAuthService() : _firebaseAuth = FirebaseAuth.instance;

  final FirebaseAuth _firebaseAuth;

  /// Stream that emits whenever auth state changes.
  Stream<User?> get authStateChanges => _firebaseAuth.authStateChanges();

  /// The currently signed-in Firebase user, or null.
  User? get currentFirebaseUser => _firebaseAuth.currentUser;

  /// Converts Firebase [User] to [AppUser].
  AppUser? userToAppUser(User? user) {
    if (user == null) return null;

    return AppUser(
      uid: user.uid,
      displayName: user.displayName ?? 'User',
      email: user.email ?? '',
      photoUrl: user.photoURL,
    );
  }

  /// Initializes GoogleSignIn.
  ///
  /// On web, we do not initialize google_sign_in because web login will use
  /// FirebaseAuth.signInWithPopup instead.
  static Future<void> initialize() async {
    if (!kIsWeb) {
      await GoogleSignIn.instance.initialize();
    }
  }

/// Triggers Google sign-in and signs into Firebase.
Future<AppUser?> signInWithGoogle() async {
  try {
    if (kIsWeb) {
      final googleProvider = GoogleAuthProvider()
        ..addScope('email')
        ..addScope('profile');

      final UserCredential userCredential =
          await _firebaseAuth.signInWithPopup(googleProvider);

      return userToAppUser(userCredential.user);
    }

    // `scopeHint` nudges Google to surface the Gmail send permission during
    // sign-in so the agent can later send outreach from the user's own
    // account. It's a hint only — identity sign-in still succeeds if the user
    // skips it, and GmailService re-requests `gmail.send` on demand at first
    // send. Send-only scope, never `gmail.readonly` (api-contract §5.3 / §11.5).
    final GoogleSignInAccount googleUser =
        await GoogleSignIn.instance.authenticate(
      scopeHint: const [GmailService.sendScope],
    );

    final GoogleSignInAuthentication googleAuth = googleUser.authentication;

    final OAuthCredential credential = GoogleAuthProvider.credential(
      idToken: googleAuth.idToken,
    );

    final UserCredential userCredential =
        await _firebaseAuth.signInWithCredential(credential);

    return userToAppUser(userCredential.user);
  } on FirebaseAuthException catch (e) {
    if (e.code == 'popup-closed-by-user' ||
        e.code == 'cancelled-popup-request' ||
        e.code == 'web-context-cancelled') {
      return null;
    }

    rethrow;
  }
}

  /// Signs out of both Google and Firebase.
  Future<void> signOut() async {
    if (!kIsWeb) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {
        // Ignore. Firebase sign-out below is what actually matters.
      }
    }

    await _firebaseAuth.signOut();
  }

  /// Deletes the current Firebase auth account. Throws
  /// `FirebaseAuthException(code: 'requires-recent-login')` if the token
  /// is older than ~5 minutes — caller should re-auth and retry.
  Future<void> deleteCurrentUser() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) return;
    await user.delete();
  }
}