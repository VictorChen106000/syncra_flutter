import 'package:flutter/foundation.dart';

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
    this.morningBriefEnabled = false,
    this.gmailConnected = false,
  });

  final String name;
  final String email;
  final String? avatarUrl;
  final String? role;
  final bool isAgentActive;
  final bool morningBriefEnabled;
  final bool gmailConnected;

  UserProfile copyWith({
    String? name,
    String? email,
    String? avatarUrl,
    String? role,
    bool? isAgentActive,
    bool? morningBriefEnabled,
    bool? gmailConnected,
  }) {
    return UserProfile(
      name: name ?? this.name,
      email: email ?? this.email,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      role: role ?? this.role,
      isAgentActive: isAgentActive ?? this.isAgentActive,
      morningBriefEnabled: morningBriefEnabled ?? this.morningBriefEnabled,
      gmailConnected: gmailConnected ?? this.gmailConnected,
    );
  }

  factory UserProfile.fromMap(Map<String, dynamic> data) {
    return UserProfile(
      name: (data['name'] as String?) ?? '',
      email: (data['email'] as String?) ?? '',
      avatarUrl: data['avatar_url'] as String?,
      role: data['role'] as String?,
      isAgentActive: (data['is_agent_active'] as bool?) ?? true,
      morningBriefEnabled: (data['morning_brief_enabled'] as bool?) ?? false,
      gmailConnected: (data['gmail_connected'] as bool?) ?? false,
    );
  }
}
