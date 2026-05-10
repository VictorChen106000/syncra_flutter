import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../models/app_user.dart';

/// Wraps [GoogleSignIn] and [FirebaseAuth] into a single service.
class GoogleAuthService {
  GoogleAuthService() : _firebaseAuth = FirebaseAuth.instance;

  final FirebaseAuth _firebaseAuth;

  /// Stream that emits whenever auth state changes (sign-in / sign-out).
  Stream<User?> get authStateChanges => _firebaseAuth.authStateChanges();

  /// The currently signed-in Firebase user, or `null`.
  User? get currentFirebaseUser => _firebaseAuth.currentUser;

  /// Converts [User] to [AppUser].
  AppUser? userToAppUser(User? user) {
    if (user == null) return null;
    return AppUser(
      uid: user.uid,
      displayName: user.displayName ?? 'User',
      email: user.email ?? '',
      photoUrl: user.photoURL,
    );
  }

  /// Initializes the GoogleSignIn plugin. Must be called once at app startup.
  static Future<void> initialize() async {
    await GoogleSignIn.instance.initialize();
  }

  /// Triggers Google account picker → signs into Firebase.
  /// Returns the [AppUser] on success, or `null` if the user cancelled.
  Future<AppUser?> signInWithGoogle() async {
    final GoogleSignInAccount googleUser;

    try {
      googleUser = await GoogleSignIn.instance.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        return null;
      }

      rethrow;
    }

    // In v7, `authentication` is a property (not a Future) and only has `idToken`.
    final GoogleSignInAuthentication googleAuth = googleUser.authentication;

    // Create a Firebase credential from the Google ID token.
    final OAuthCredential credential = GoogleAuthProvider.credential(
      idToken: googleAuth.idToken,
    );

    // Sign in to Firebase with the Google credential.
    final UserCredential userCredential = await _firebaseAuth
        .signInWithCredential(credential);

    return userToAppUser(userCredential.user);
  }

  /// Signs out of both Google and Firebase.
  Future<void> signOut() async {
    await _firebaseAuth.signOut();

    try {
      await GoogleSignIn.instance.signOut();
    } catch (e) {
      debugPrint('Google Sign-Out cleanup failed: $e');
    }
  }
}
