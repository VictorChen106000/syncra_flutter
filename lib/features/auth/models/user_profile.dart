import 'package:flutter/foundation.dart';

import '../../resumes/models/resume_fit.dart';

/// Snapshot of `users/{uid}` — settings the user controls.
///
/// Mirrors the schema in [docs/api-contract.md §3]. Immutable; mutations
/// go through `UserProfileNotifier`, which writes via `UserRepository.update()`.
@immutable
class UserProfile {
  const UserProfile({
    required this.name,
    required this.email,
    this.avatarUrl,
    this.role,
    this.isAgentActive = true,
    this.gmailConnected = false,
    this.hasCompletedOnboarding = false,
    this.resumeFit,
  });

  final String name;
  final String email;
  final String? avatarUrl;
  final String? role;
  final bool isAgentActive;
  final bool gmailConnected;

  /// True once the user has finished (or explicitly skipped) the first-run
  /// onboarding flow. The router redirect keys off this — *not* off `role`
  /// being non-empty — so Skip can drop the user on the dashboard without
  /// forging a placeholder role.
  final bool hasCompletedOnboarding;

  /// Persisted snapshot of the agent's resume-fit pie. Written when the
  /// onboarding agent calls `propose_fit_chart`; read by the dashboard's
  /// "Chart" view so the chart survives across sessions and re-renders
  /// without a fresh agent call.
  final ResumeFit? resumeFit;

  UserProfile copyWith({
    String? name,
    String? email,
    String? avatarUrl,
    String? role,
    bool? isAgentActive,
    bool? gmailConnected,
    bool? hasCompletedOnboarding,
    ResumeFit? resumeFit,
    bool clearResumeFit = false,
  }) {
    return UserProfile(
      name: name ?? this.name,
      email: email ?? this.email,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      role: role ?? this.role,
      isAgentActive: isAgentActive ?? this.isAgentActive,
      gmailConnected: gmailConnected ?? this.gmailConnected,
      hasCompletedOnboarding:
          hasCompletedOnboarding ?? this.hasCompletedOnboarding,
      resumeFit: clearResumeFit ? null : (resumeFit ?? this.resumeFit),
    );
  }

  factory UserProfile.fromMap(Map<String, dynamic> data) {
    final rawFit = data['resume_fit'];
    return UserProfile(
      name: (data['name'] as String?) ?? '',
      email: (data['email'] as String?) ?? '',
      avatarUrl: data['avatar_url'] as String?,
      role: data['role'] as String?,
      isAgentActive: (data['is_agent_active'] as bool?) ?? true,
      gmailConnected: (data['gmail_connected'] as bool?) ?? false,
      // Legacy users (created before this flag existed) are migrated lazily:
      // a non-empty `role` is treated as proof they already finished onboarding
      // in the old flow, so they don't get re-prompted on next sign-in.
      hasCompletedOnboarding:
          (data['has_completed_onboarding'] as bool?) ??
              ((data['role'] as String?)?.trim().isNotEmpty ?? false),
      resumeFit: rawFit is Map
          ? ResumeFit.fromJson(rawFit.cast<String, dynamic>())
          : null,
    );
  }
}
