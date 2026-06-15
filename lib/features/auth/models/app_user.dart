class AppUser {
  const AppUser({
    required this.uid,
    required this.displayName,
    required this.email,
    this.photoUrl,
    this.isGuest = false,
  });

  final String uid;
  final String displayName;
  final String email;
  final String? photoUrl;
  final bool isGuest;

  /// Creates a guest user with no real identity.
  factory AppUser.guest() {
    return const AppUser(
      uid: 'guest',
      displayName: 'Guest',
      email: '',
      isGuest: true,
    );
  }

  /// The first letter of the display name, for avatar fallback.
  String get initial =>
      displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';
}
