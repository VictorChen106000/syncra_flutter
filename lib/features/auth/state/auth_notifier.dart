import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/firestore/user_repository.dart';
import '../models/app_user.dart';
import '../services/google_auth_service.dart';

@immutable
class AuthState {
  const AuthState({
    this.appUser,
    this.isLoading = false,
    this.error,
  });

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
  AuthNotifier({
    GoogleAuthService? authService,
    UserRepository? userRepository,
  })  : _authService = authService ?? GoogleAuthService(),
        _userRepository = userRepository ?? UserRepository();

  final GoogleAuthService _authService;
  final UserRepository _userRepository;
  StreamSubscription? _authSubscription;

  @override
  AuthState build() {
    _authSubscription = _authService.authStateChanges.listen((firebaseUser) async {
      if (firebaseUser != null) {
        state = state.copyWith(appUser: _authService.userToAppUser(firebaseUser));
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
      appUser: existingUser != null ? _authService.userToAppUser(existingUser) : null,
    );
  }

  Future<void> signInWithGoogle() async {
    if (state.isLoading) return;

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final user = await _authService
          .signInWithGoogle()
          .timeout(const Duration(seconds: 8), onTimeout: () => null);

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

  /// Email/password sign-in.
  ///
  /// Backend wiring (Firebase Auth `signInWithEmailAndPassword`) lives in
  /// the auth service. For now this stub validates inputs and falls through
  /// to a guest session keyed by the email so the demo flow continues —
  /// swap the body for `_authService.signInWithEmail(...)` once the
  /// service method is implemented.
  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    if (state.isLoading) return;
    final trimmedEmail = email.trim();
    if (trimmedEmail.isEmpty || password.isEmpty) {
      state = state.copyWith(error: 'Enter both email and password.');
      return;
    }

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final namePart = trimmedEmail.split('@').first;
      final displayName = namePart.isEmpty ? 'You' : namePart;
      state = state.copyWith(
        appUser: AppUser(
          uid: 'email-${trimmedEmail.hashCode.abs()}',
          displayName: displayName,
          email: trimmedEmail,
          isGuest: true,
        ),
        isLoading: false,
      );
    } catch (e) {
      debugPrint('Email Sign-In Error: $e');
      state = state.copyWith(
        isLoading: false,
        error: 'Sign-in failed. Check your details.',
      );
    }
  }

  Future<void> signOut() async {
    state = state.copyWith(isLoading: true);

    try {
      if (state.appUser != null && !state.appUser!.isGuest) {
        await _authService.signOut();
      }
      state = state.copyWith(clearUser: true, isLoading: false, clearError: true);
    } catch (e) {
      debugPrint('Sign-Out Error: $e');
      state = state.copyWith(
        clearUser: true,
        isLoading: false,
        error: 'Sign-out failed. Please try again.',
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

final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);
