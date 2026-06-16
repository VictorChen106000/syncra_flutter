class AppUser {
  const AppUser({
    required this.uid,
    required this.displayName,
    required this.email,
    this.photoUrl,
  });

  final String uid;
  final String displayName;
  final String email;
  final String? photoUrl;

  /// The first letter of the display name, for avatar fallback.
  String get initial =>
      displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';
}
