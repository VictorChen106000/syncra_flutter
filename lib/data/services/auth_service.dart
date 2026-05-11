import '../../core/network/api_client.dart';
import '../models/user.dart';
import '../repositories/auth_repository.dart';

class AuthService implements AuthRepository {
  AuthService(this._client);

  final ApiClient _client;

  @override
  Future<User> signInWithGoogle() async {
    final json = await _client.post('/auth/google', {});
    return User.fromJson(json);
  }

  @override
  Future<User> signInWithApple() async {
    final json = await _client.post('/auth/apple', {});
    return User.fromJson(json);
  }

  @override
  Future<User> signInAsGuest() async {
    final json = await _client.post('/auth/guest', {});
    return User.fromJson(json);
  }

  @override
  Future<void> signOut() async {
    await _client.post('/auth/sign-out', {});
  }

  @override
  Future<User?> getCurrentUser() async {
    final json = await _client.get('/auth/me');
    return User.fromJson(json);
  }
}
