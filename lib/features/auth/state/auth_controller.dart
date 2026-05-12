import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/app_user.dart';
import '../services/google_auth_service.dart';

/// Manages authentication state for the entire app.
///
/// Provides [appUser], [isSignedIn], [isLoading], and [error] to consumers.
class AuthController extends ChangeNotifier {
  AuthController() : _authService = GoogleAuthService() {
    // Listen to Firebase auth state changes so we stay in sync
    // (e.g., if the token expires or user signs out from another device).
    _authSubscription = _authService.authStateChanges.listen((firebaseUser) {
      if (firebaseUser != null) {
        _appUser = _authService.userToAppUser(firebaseUser);
      } else if (_appUser != null && !_appUser!.isGuest) {
        // Only clear if it was a real (non-guest) user that signed out.
        _appUser = null;
      }
      notifyListeners();
    });

    // Check if there's already a signed-in user from a previous session.
    final existingUser = _authService.currentFirebaseUser;
    if (existingUser != null) {
      _appUser = _authService.userToAppUser(existingUser);
    }
  }

  final GoogleAuthService _authService;
  StreamSubscription? _authSubscription;

  AppUser? _appUser;
  bool _isLoading = false;
  String? _error;

  /// The currently signed-in user, or `null` if not signed in.
  AppUser? get appUser => _appUser;

  /// Whether a user (including guest) is currently signed in.
  bool get isSignedIn => _appUser != null;

  /// Whether an auth operation is in progress.
  bool get isLoading => _isLoading;

  /// The last error message, if any.
  String? get error => _error;

  /// Sign in with Google account via Firebase.
  Future<void> signInWithGoogle() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final user = await _authService.signInWithGoogle();
      if (user != null) {
        _appUser = user;
      }
      // If user is null, the user cancelled — not an error.
    } catch (e) {
      _error = 'Sign-in failed. Please try again.';
      debugPrint('Google Sign-In Error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Continue without authentication.
  void continueAsGuest() {
    _appUser = AppUser.guest();
    _error = null;
    notifyListeners();
  }

  /// Sign out and clear the user.
  Future<void> signOut() async {
    _isLoading = true;
    notifyListeners();

    try {
      if (_appUser != null && !_appUser!.isGuest) {
        await _authService.signOut();
      }
      _error = null;
    } catch (e) {
      _error = 'Sign-out failed. Please try again.';
      debugPrint('Sign-Out Error: $e');
    } finally {
      // Always clear local state so the router redirects to login,
      // even if the underlying Firebase/Google call threw.
      _appUser = null;
      _isLoading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}
