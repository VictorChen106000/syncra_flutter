import 'package:flutter/foundation.dart';

import '../../resumes/models/resume_fit.dart';

@immutable
class AutoApplySettings {
  const AutoApplySettings({
    this.enabled = false,
    this.minQualityScore = 85,
    this.maxDailyApplications = 3,
    this.autoSendOutreach = false,
  });

  final bool enabled;
  final int minQualityScore;
  final int maxDailyApplications;

  /// When true, the agent may send a drafted outreach email automatically
  /// instead of stopping at the review sheet — but only when bounded
  /// auto-apply is enabled, the job is low risk, and the recipient is
  /// confirmed/high-confidence (see `shouldAutoSendOutreach`). Off by default;
  /// the user opts in from Profile. Medium/high-risk postings and guessed
  /// recipients always fall back to manual review.
  final bool autoSendOutreach;

  AutoApplySettings copyWith({
    bool? enabled,
    int? minQualityScore,
    int? maxDailyApplications,
    bool? autoSendOutreach,
  }) {
    return AutoApplySettings(
      enabled: enabled ?? this.enabled,
      minQualityScore: minQualityScore ?? this.minQualityScore,
      maxDailyApplications: maxDailyApplications ?? this.maxDailyApplications,
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

/// How far the chat agent advances on its own before it waits for the user.
///
/// A single, deterministic dial the agent reads from the profile instead of
/// inferring scope from the user's wording. The levels escalate monotonically
/// across the pipeline (find → match → tailor → draft → send):
/// - [assist]: proposes each step, waits for approval before the next.
/// - [autoDraft]: chains the full stated goal to a ready-to-send draft; stops
///   only at the two human gates — Save résumé + tap Send.
/// - [autopilot] (default): also auto-sends low-risk drafts, behind a brief
///   undo window.
///
/// Only the level itself is trusted to the model; the irreversible send stays
/// code-gated by the email confirmation token regardless of this setting.
enum AutonomyLevel {
  assist,
  autoDraft,
  autopilot;

  /// Stable key persisted to Firestore (`autonomy_level`).
  String get storageKey => switch (this) {
    AutonomyLevel.assist => 'assist',
    AutonomyLevel.autoDraft => 'auto_draft',
    AutonomyLevel.autopilot => 'autopilot',
  };

  /// Short user-facing name for the settings dial.
  String get label => switch (this) {
    AutonomyLevel.assist => 'Assist',
    AutonomyLevel.autoDraft => 'Auto-draft',
    AutonomyLevel.autopilot => 'Autopilot',
  };

  /// Derives the bounded auto-apply guardrails this autonomy level implies,
  /// starting from the user's [current] settings so customised quality / daily
  /// limits are preserved. Agent Autonomy is the single user-facing control;
  /// this keeps the internal [AutoApplySettings] in lockstep with it.
  ///
  /// Only [autopilot] enables auto-apply and auto-send; [assist] and
  /// [autoDraft] keep the agent stopping at the human gates. This sets *intent*
  /// only — the irreversible send stays gated by every check in
  /// `shouldAutoSendOutreach` (confirmed recipient, quality, daily limit), so
  /// guessed recipients never auto-send regardless.
  AutoApplySettings applyToAutoApply(AutoApplySettings current) =>
      switch (this) {
        AutonomyLevel.assist || AutonomyLevel.autoDraft => current.copyWith(
          enabled: false,
          autoSendOutreach: false,
        ),
        // minQualityScore / maxDailyApplications fall through copyWith
        // unchanged — keeping any existing value, or the model defaults
        // (85% / 3 a day) for a fresh profile.
        AutonomyLevel.autopilot => current.copyWith(
          enabled: true,
          autoSendOutreach: true,
        ),
      };

  /// Parses the persisted key, defaulting to [autopilot] for legacy users and
  /// any unrecognised value.
  static AutonomyLevel fromStorage(Object? value) => switch (value) {
    'assist' => AutonomyLevel.assist,
    'auto_draft' => AutonomyLevel.autoDraft,
    _ => AutonomyLevel.autopilot,
  };
}

/// Where the agent looks for jobs — maps directly to JSearch's `country`
/// query parameter (an ISO 3166-1 alpha-2 code). JSearch itself defaults to
/// the United States when no country is sent, so [unitedStates] keeps the
/// pre-region behaviour unchanged; the user picks another region from
/// onboarding or Profile to search there instead.
///
/// A curated, demo-friendly set rather than every country JSearch supports —
/// enough breadth to be useful without turning the picker into a 200-row list.
enum JobRegion {
  unitedStates('us', 'United States', '🇺🇸'),
  taiwan('tw', 'Taiwan', '🇹🇼'),
  singapore('sg', 'Singapore', '🇸🇬'),
  hongKong('hk', 'Hong Kong', '🇭🇰'),
  japan('jp', 'Japan', '🇯🇵'),
  unitedKingdom('gb', 'United Kingdom', '🇬🇧'),
  canada('ca', 'Canada', '🇨🇦'),
  australia('au', 'Australia', '🇦🇺');

  const JobRegion(this.code, this.label, this.flag);

  /// ISO 3166-1 alpha-2 code, lowercased — sent verbatim as JSearch's
  /// `country` param and persisted to Firestore (`job_region`).
  final String code;

  /// Short user-facing name for the picker.
  final String label;

  /// Flag emoji shown beside the label so the choice reads at a glance.
  final String flag;

  /// Parses the persisted code, defaulting to [unitedStates] for new and
  /// legacy profiles and any unrecognised value.
  static JobRegion fromStorage(Object? value) {
    final code = value is String ? value.trim().toLowerCase() : '';
    for (final region in JobRegion.values) {
      if (region.code == code) return region;
    }
    return JobRegion.unitedStates;
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
    this.recommendation,
    this.autoApplySettings = const AutoApplySettings(),
    this.autonomyLevel = AutonomyLevel.autopilot,
    this.jobRegion = JobRegion.unitedStates,
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

  /// The agent's one- or two-line read on the user, written *to* them during
  /// onboarding (where they're strongest + the next move it would make). The
  /// dashboard lands on this so the agent's onboarding thought finishes there
  /// rather than restarting. Null until the first setup run produces it.
  final String? recommendation;

  /// User-defined guardrails for future bounded auto-apply behavior.
  ///
  /// This does not auto-send anything by itself; it only stores the safe
  /// boundaries the agent must obey later.
  final AutoApplySettings autoApplySettings;

  /// How far the chat agent advances before it waits for the user. Defaults to
  /// [AutonomyLevel.autopilot] for new and legacy profiles.
  final AutonomyLevel autonomyLevel;

  /// Which country the agent searches for jobs in (JSearch's `country` param).
  /// Defaults to [JobRegion.unitedStates], matching JSearch's own default, so
  /// legacy profiles behave exactly as before until the user picks a region.
  final JobRegion jobRegion;

  UserProfile copyWith({
    String? name,
    String? email,
    String? avatarUrl,
    String? role,
    bool? isAgentActive,
    bool? gmailConnected,
    bool? hasCompletedOnboarding,
    ResumeFit? resumeFit,
    String? recommendation,
    AutoApplySettings? autoApplySettings,
    AutonomyLevel? autonomyLevel,
    JobRegion? jobRegion,
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
      recommendation: recommendation ?? this.recommendation,
      autoApplySettings: autoApplySettings ?? this.autoApplySettings,
      autonomyLevel: autonomyLevel ?? this.autonomyLevel,
      jobRegion: jobRegion ?? this.jobRegion,
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
      recommendation:
          (data['recommendation'] as String?)?.trim().isEmpty ?? true
          ? null
          : (data['recommendation'] as String).trim(),
      autoApplySettings: AutoApplySettings.fromMap(data['auto_apply']),
      autonomyLevel: AutonomyLevel.fromStorage(data['autonomy_level']),
      jobRegion: JobRegion.fromStorage(data['job_region']),
    );
  }
}
