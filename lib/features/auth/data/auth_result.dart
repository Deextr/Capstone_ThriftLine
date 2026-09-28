import '../domain/auth_user.dart';

/// Result of an authentication attempt.
class AuthResult {
  const AuthResult._({
    required this.success,
    this.user,
    this.errorMessage,
    this.requiresEmailVerification = false,
    this.requiresEmailOtp = false,
  });

  final bool success;
  final AuthUser? user;
  final String? errorMessage;

  /// Supabase created the account but withheld a session until the address is
  /// confirmed via the link it emailed.
  final bool requiresEmailVerification;

  /// Password succeeded and a session exists; the user must still enter the
  /// 6-digit email OTP before the app treats them as fully signed in.
  final bool requiresEmailOtp;

  factory AuthResult.success(
    AuthUser? user, {
    bool requiresEmailVerification = false,
    bool requiresEmailOtp = false,
  }) => AuthResult._(
    success: true,
    user: user,
    requiresEmailVerification: requiresEmailVerification,
    requiresEmailOtp: requiresEmailOtp,
  );

  factory AuthResult.failure(String message) =>
      AuthResult._(success: false, errorMessage: message);
}
