/// Mirrors CEYLORA.Application.DTOs.Auth.AuthResponseDto.
class AuthSession {
  final String token;
  final String email;
  final String fullName;
  final String role;
  final DateTime expiresAt;

  const AuthSession({
    required this.token,
    required this.email,
    required this.fullName,
    required this.role,
    required this.expiresAt,
  });

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
        token: json['token'] as String,
        email: json['email'] as String,
        fullName: json['fullName'] as String,
        role: json['role'] as String,
        expiresAt: DateTime.parse(json['expiresAt'] as String).toUtc(),
      );

  Map<String, dynamic> toJson() => {
        'token': token,
        'email': email,
        'fullName': fullName,
        'role': role,
        'expiresAt': expiresAt.toIso8601String(),
      };

  bool get isExpired => !expiresAt.isAfter(DateTime.now().toUtc());
}
