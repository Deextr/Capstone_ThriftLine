import '../domain/auth_user.dart';

/// Result of an authentication attempt.
class AuthResult {
  const AuthResult._({
    required this.success,
    this.user,
    this.errorMessage,
  });

  final bool success;
  final AuthUser? user;
  final String? errorMessage;

  factory AuthResult.success(AuthUser user) => AuthResult._(
        success: true,
        user: user,
      );

  factory AuthResult.failure(String message) => AuthResult._(
        success: false,
        errorMessage: message,
      );
}
