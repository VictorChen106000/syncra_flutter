import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/firestore/user_repository.dart';
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

  Future<void> setAutonomyLevel(AutonomyLevel level) async {
    final uid = _boundUid;
    if (uid == null) return;
    state = state?.copyWith(autonomyLevel: level);
    try {
      await _repository.update(uid, autonomyLevel: level);
    } catch (e) {
      debugPrint('setAutonomyLevel failed: $e');
    }
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
}

final userProfileProvider =
    NotifierProvider<UserProfileNotifier, UserProfile?>(UserProfileNotifier.new);
