import '../domain/auth_user.dart';

/// Result of an authentication attempt.
class AuthResult {
  const AuthResult._({
    required this.success,
    this.user,
    this.errorMessage,
    this.requiresEmailVerification = false,
  });

  final bool success;
  final AuthUser? user;
  final String? errorMessage;
  final bool requiresEmailVerification;

  factory AuthResult.success(
    AuthUser? user, {
    bool requiresEmailVerification = false,
  }) => AuthResult._(
    success: true,
    user: user,
    requiresEmailVerification: requiresEmailVerification,
  );

  factory AuthResult.failure(String message) =>
      AuthResult._(success: false, errorMessage: message);
}
