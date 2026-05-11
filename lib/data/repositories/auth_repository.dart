import '../models/user.dart';

abstract class AuthRepository {
  Future<User> signInWithGoogle();
  Future<User> signInWithApple();
  Future<User> signInAsGuest();
  Future<void> signOut();
  Future<User?> getCurrentUser();
}
