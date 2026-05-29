import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/firestore/user_repository.dart';
import '../../resumes/models/resume_fit.dart';
import '../models/user_profile.dart';
import 'auth_notifier.dart';

/// Streamed snapshot of `users/{uid}`. Settings page binds reads/writes here.
///
/// Rebinds to the current uid whenever `authProvider` changes (sign-in,
/// sign-out, account swap). Guests get a `null` profile.
class UserProfileNotifier extends Notifier<UserProfile?> {
  UserProfileNotifier({UserRepository? repository})
      : _repository = repository ?? UserRepository();

  final UserRepository _repository;

  StreamSubscription<UserProfile?>? _subscription;
  String? _boundUid;

  @override
  UserProfile? build() {
    final auth = ref.watch(authProvider);
    _bindTo(auth.appUser?.uid, auth.appUser?.isGuest ?? true);

    ref.onDispose(() {
      _subscription?.cancel();
      _subscription = null;
    });

    return null;
  }

  void _bindTo(String? uid, bool isGuest) {
    if (uid == _boundUid && _subscription != null) return;

    _subscription?.cancel();
    _subscription = null;

    if (uid == null || isGuest) {
      _boundUid = null;
      // Don't touch `state` here — this method is called from build() before
      // the initial state has been published. build()'s return value (null)
      // is what initializes / resets state.
      return;
    }

    _boundUid = uid;
    _subscription = _repository.watchProfile(uid).listen(
      (profile) {
        state = profile;
      },
      onError: (Object e) {
        debugPrint('user profile stream error: $e');
      },
    );
  }

  Future<void> setMorningBriefEnabled(bool enabled) async {
    final uid = _boundUid;
    if (uid == null) return;
    state = state?.copyWith(morningBriefEnabled: enabled);
    try {
      await _repository.update(uid, morningBriefEnabled: enabled);
    } catch (e) {
      debugPrint('setMorningBriefEnabled failed: $e');
    }
  }

  Future<void> setRole(String role) async {
    final uid = _boundUid;
    if (uid == null) return;
    final trimmed = role.trim();
    state = state?.copyWith(role: trimmed);
    try {
      await _repository.update(uid, role: trimmed);
    } catch (e) {
      debugPrint('setRole failed: $e');
    }
  }

  Future<void> setGmailConnected(bool connected) async {
    final uid = _boundUid;
    if (uid == null) return;
    state = state?.copyWith(gmailConnected: connected);
    try {
      await _repository.update(uid, gmailConnected: connected);
    } catch (e) {
      debugPrint('setGmailConnected failed: $e');
    }
  }

  Future<void> setAgentActive(bool active) async {
    final uid = _boundUid;
    if (uid == null) return;
    state = state?.copyWith(isAgentActive: active);
    try {
      await _repository.update(uid, isAgentActive: active);
    } catch (e) {
      debugPrint('setAgentActive failed: $e');
    }
  }

  /// Flips the user past first-run setup. Called by the Skip button (which
  /// leaves `role` untouched). Used by the router redirect to decide whether
  /// the user still needs the onboarding surface.
  Future<void> setHasCompletedOnboarding(bool completed) async {
    final uid = _boundUid;
    if (uid == null) return;
    state = state?.copyWith(hasCompletedOnboarding: completed);
    try {
      await _repository.update(uid, hasCompletedOnboarding: completed);
    } catch (e) {
      debugPrint('setHasCompletedOnboarding failed: $e');
    }
  }

  /// Persists the agent's read on the user's resume. Written during onboarding
  /// once the resume is parsed and the role-fit is inferred — the dashboard's
  /// "Chart" view reads from this so the visualisation survives across sessions
  /// without re-running the agent.
  Future<void> setResumeFit(ResumeFit fit) async {
    final uid = _boundUid;
    if (uid == null) return;
    state = state?.copyWith(resumeFit: fit);
    try {
      await _repository.update(uid, resumeFit: fit);
    } catch (e) {
      debugPrint('setResumeFit failed: $e');
    }
  }

  /// Writes the captured role and flips `hasCompletedOnboarding` in a single
  /// Firestore round-trip — used by `complete_onboarding`. Doing both in one
  /// `update()` keeps the profile stream from briefly emitting a state where
  /// role is set but the gate flag is still false (which would trip the
  /// router back to /onboarding mid-transition).
  Future<void> setRoleAndComplete(String role) async {
    final uid = _boundUid;
    if (uid == null) return;
    final trimmed = role.trim();
    state = state?.copyWith(role: trimmed, hasCompletedOnboarding: true);
    try {
      await _repository.update(
        uid,
        role: trimmed,
        hasCompletedOnboarding: true,
      );
    } catch (e) {
      debugPrint('setRoleAndComplete failed: $e');
    }
  }
}

final userProfileProvider =
    NotifierProvider<UserProfileNotifier, UserProfile?>(UserProfileNotifier.new);
