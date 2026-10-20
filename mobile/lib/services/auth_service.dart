import '../models/auth_session.dart';
import 'api_client.dart';

class AuthService {
  final ApiClient _api;
  AuthService(this._api);

  Future<AuthSession> login(String email, String password) async {
    final data = await _api.post('/api/auth/login', {
      'email': email,
      'password': password,
    });
    return AuthSession.fromJson(data as Map<String, dynamic>);
  }

  /// Mobile self-registration is always for the Traveler role.
  Future<AuthSession> register(
      String fullName, String email, String password) async {
    final data = await _api.post('/api/auth/register', {
      'fullName': fullName,
      'email': email,
      'password': password,
      'roleName': 'Traveler',
    });
    return AuthSession.fromJson(data as Map<String, dynamic>);
  }
}
