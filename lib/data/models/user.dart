class User {
  const User({
    required this.id,
    required this.name,
    required this.email,
    this.role,
    this.avatarUrl,
    this.isAgentActive = false,
  });

  final String id;
  final String name;
  final String email;
  final String? role;
  final String? avatarUrl;
  final bool isAgentActive;

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'] as String,
        name: json['name'] as String,
        email: json['email'] as String,
        role: json['role'] as String?,
        avatarUrl: json['avatar_url'] as String?,
        isAgentActive: json['is_agent_active'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'role': role,
        'avatar_url': avatarUrl,
        'is_agent_active': isAgentActive,
      };
}
