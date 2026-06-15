import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/firestore/user_repository.dart';
import '../models/app_user.dart';
import '../services/google_auth_service.dart';

@immutable
class AuthState {
  const AuthState({this.appUser, this.isLoading = false, this.error});

  final AppUser? appUser;
  final bool isLoading;
  final String? error;

  bool get isSignedIn => appUser != null;

  AuthState copyWith({
    AppUser? appUser,
    bool? isLoading,
    String? error,
    bool clearUser = false,
    bool clearError = false,
  }) {
    return AuthState(
      appUser: clearUser ? null : (appUser ?? this.appUser),
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class AuthNotifier extends Notifier<AuthState> {
  AuthNotifier({GoogleAuthService? authService, UserRepository? userRepository})
    : _injectedAuthService = authService,
      _injectedUserRepository = userRepository;

  // Built lazily on first use, not in the field initializer, so a test
  // subclass that overrides `build()` never triggers `FirebaseAuth.instance`
  // (which needs `Firebase.initializeApp`). Production code path is unchanged.
  final GoogleAuthService? _injectedAuthService;
  final UserRepository? _injectedUserRepository;
  GoogleAuthService? _authServiceCache;
  UserRepository? _userRepositoryCache;

  GoogleAuthService get _authService =>
      _authServiceCache ??= _injectedAuthService ?? GoogleAuthService();
  UserRepository get _userRepository =>
      _userRepositoryCache ??= _injectedUserRepository ?? UserRepository();

  StreamSubscription? _authSubscription;

  @override
  AuthState build() {
    _authSubscription = _authService.authStateChanges.listen((
      firebaseUser,
    ) async {
      if (firebaseUser != null) {
        state = state.copyWith(
          appUser: _authService.userToAppUser(firebaseUser),
        );
        try {
          await _userRepository.ensureUserDoc(firebaseUser);
        } catch (e) {
          debugPrint('ensureUserDoc failed: $e');
        }
      } else if (state.appUser != null && !state.appUser!.isGuest) {
        state = state.copyWith(clearUser: true);
      }
    });

    ref.onDispose(() {
      _authSubscription?.cancel();
    });

    final existingUser = _authService.currentFirebaseUser;
    return AuthState(
      appUser: existingUser != null
          ? _authService.userToAppUser(existingUser)
          : null,
    );
  }

  Future<void> signInWithGoogle() async {
    if (state.isLoading) return;

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final user = await _authService.signInWithGoogle().timeout(
        const Duration(seconds: 8),
        onTimeout: () => null,
      );

      if (user != null) {
        state = state.copyWith(appUser: user, isLoading: false);
      } else {
        state = state.copyWith(isLoading: false);
      }
    } catch (e) {
      debugPrint('Google Sign-In Error: $e');
      state = state.copyWith(
        isLoading: false,
        error: 'Sign-in failed. Please try again.',
      );
    }
  }

  void continueAsGuest() {
    state = state.copyWith(appUser: AppUser.guest(), clearError: true);
  }

  /// Signs in an existing account with Firebase email/password auth.
  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) => _emailAuth(email: email, password: password, isCreate: false);

  /// Creates a new Firebase email/password account, then signs in.
  Future<void> signUpWithEmail({
    required String email,
    required String password,
  }) => _emailAuth(email: email, password: password, isCreate: true);

  Future<void> _emailAuth({
    required String email,
    required String password,
    required bool isCreate,
  }) async {
    if (state.isLoading) return;
    final trimmedEmail = email.trim();
    if (trimmedEmail.isEmpty || password.isEmpty) {
      state = state.copyWith(error: 'Enter both email and password.');
      return;
    }

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final user = isCreate
          ? await _authService.signUpWithEmail(
              email: trimmedEmail,
              password: password,
            )
          : await _authService.signInWithEmail(
              email: trimmedEmail,
              password: password,
            );
      // The authStateChanges listener also publishes the user and runs
      // ensureUserDoc; set it here too for immediate UI feedback.
      state = state.copyWith(appUser: user, isLoading: false);
    } on FirebaseAuthException catch (e) {
      debugPrint('Email auth error: ${e.code}');
      state = state.copyWith(isLoading: false, error: _emailAuthError(e));
    } catch (e) {
      debugPrint('Email auth error: $e');
      state = state.copyWith(
        isLoading: false,
        error: 'Sign-in failed. Please try again.',
      );
    }
  }

  String _emailAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'That email address looks invalid.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password.';
      case 'email-already-in-use':
        return 'An account already exists for that email.';
      case 'weak-password':
        return 'Password must be at least 6 characters.';
      case 'network-request-failed':
        return 'Network error. Check your connection.';
      case 'too-many-requests':
        return 'Too many attempts. Try again later.';
      default:
        return 'Sign-in failed. Please try again.';
    }
  }

  Future<void> signOut() async {
    state = state.copyWith(isLoading: true);

    try {
      if (state.appUser != null && !state.appUser!.isGuest) {
        await _authService.signOut();
      }
      state = state.copyWith(
        clearUser: true,
        isLoading: false,
        clearError: true,
      );
    } catch (e) {
      debugPrint('Sign-Out Error: $e');
      state = state.copyWith(
        clearUser: true,
        isLoading: false,
        error: 'Sign-out failed. Please try again.',
      );
    }
  }

  /// Wipes every user-owned subcollection and rolls the `users/{uid}` profile
  /// back to first-run, so the user stays signed in but is dropped through
  /// onboarding again — a true "start over". See [UserRepository.resetUserData].
  Future<void> resetAccountData() async {
    final user = state.appUser;
    if (user == null || user.isGuest) return;

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _userRepository.resetUserData(user.uid);
      state = state.copyWith(isLoading: false);
    } catch (e) {
      debugPrint('Reset account error: $e');
      state = state.copyWith(
        isLoading: false,
        error: 'Could not reset your account. Try again.',
      );
    }
  }

  /// Deletes the user's Firestore profile doc and Firebase auth account.
  ///
  /// Sub-collections (resumes/applications/etc.) are not cascaded — owner-only
  /// security rules will block further reads/writes once the auth user is
  /// gone, and the docs can be cleaned up out-of-band. For v1 demo, that's
  /// acceptable.
  ///
  /// May fail with `requires-recent-login`. Caller can sign in again and retry.
  Future<void> deleteAccount() async {
    final user = state.appUser;
    if (user == null || user.isGuest) return;

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      try {
        await _userRepository.deleteUserDoc(user.uid);
      } catch (e) {
        debugPrint('deleteUserDoc failed (continuing): $e');
      }
      await _authService.deleteCurrentUser();
      state = state.copyWith(clearUser: true, isLoading: false);
    } catch (e) {
      debugPrint('Delete account error: $e');
      state = state.copyWith(
        isLoading: false,
        error: e.toString().contains('requires-recent-login')
            ? 'Please sign in again to confirm account deletion.'
            : 'Could not delete your account. Try again.',
      );
    }
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);
