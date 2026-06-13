import 'package:flutter/foundation.dart';

import '../../resumes/models/resume_fit.dart';

@immutable
class AutoApplySettings {
  const AutoApplySettings({
    this.enabled = false,
    this.minQualityScore = 85,
    this.maxDailyApplications = 3,
    this.requireLowTrust = true,
    this.autoSendOutreach = false,
  });

  final bool enabled;
  final int minQualityScore;
  final int maxDailyApplications;
  final bool requireLowTrust;

  /// When true, the agent may send a drafted outreach email automatically
  /// instead of stopping at the review sheet — but only for low-risk jobs
  /// (see `shouldAutoSendOutreach`). Off by default; the user opts in from
  /// Profile. Medium/high-risk postings always fall back to manual review.
  final bool autoSendOutreach;

  AutoApplySettings copyWith({
    bool? enabled,
    int? minQualityScore,
    int? maxDailyApplications,
    bool? requireLowTrust,
    bool? autoSendOutreach,
  }) {
    return AutoApplySettings(
      enabled: enabled ?? this.enabled,
      minQualityScore: minQualityScore ?? this.minQualityScore,
      maxDailyApplications: maxDailyApplications ?? this.maxDailyApplications,
      requireLowTrust: requireLowTrust ?? this.requireLowTrust,
      autoSendOutreach: autoSendOutreach ?? this.autoSendOutreach,
    );
  }

  factory AutoApplySettings.fromMap(Object? value) {
    if (value is! Map) return const AutoApplySettings();

    return AutoApplySettings(
      enabled: _boolOrFallback(value['enabled'], fallback: false),
      minQualityScore: _intInRange(
        value['min_quality_score'],
        min: 60,
        max: 100,
        fallback: 85,
      ),
      maxDailyApplications: _intInRange(
        value['max_daily_applications'],
        min: 1,
        max: 10,
        fallback: 3,
      ),
      requireLowTrust: _boolOrFallback(
        value['require_low_trust'],
        fallback: true,
      ),
      autoSendOutreach: _boolOrFallback(
        value['auto_send_outreach'],
        fallback: false,
      ),
    );
  }

  Map<String, dynamic> toMap() => {
    'enabled': enabled,
    'min_quality_score': minQualityScore,
    'max_daily_applications': maxDailyApplications,
    'require_low_trust': requireLowTrust,
    'auto_send_outreach': autoSendOutreach,
  };

  static int _intInRange(
    Object? value, {
    required int min,
    required int max,
    required int fallback,
  }) {
    final parsed = value is num ? value.toInt() : null;
    if (parsed == null) return fallback;
    return parsed.clamp(min, max).toInt();
  }

  static bool _boolOrFallback(Object? value, {required bool fallback}) {
    return value is bool ? value : fallback;
  }
}

/// Snapshot of `users/{uid}` — settings the user controls.
///
/// Mirrors the user profile schema documented in `docs/ARCHITECTURE.md`.
/// Immutable; mutations go through `UserProfileNotifier`, which writes via
/// `UserRepository.update()`.
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
    this.autoApplySettings = const AutoApplySettings(),
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

  /// User-defined guardrails for future bounded auto-apply behavior.
  ///
  /// This does not auto-send anything by itself; it only stores the safe
  /// boundaries the agent must obey later.
  final AutoApplySettings autoApplySettings;

  UserProfile copyWith({
    String? name,
    String? email,
    String? avatarUrl,
    String? role,
    bool? isAgentActive,
    bool? gmailConnected,
    bool? hasCompletedOnboarding,
    ResumeFit? resumeFit,
    AutoApplySettings? autoApplySettings,
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
      autoApplySettings: autoApplySettings ?? this.autoApplySettings,
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
      autoApplySettings: AutoApplySettings.fromMap(data['auto_apply']),
    );
  }
}
