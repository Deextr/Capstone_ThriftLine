/// Outcome of an email/password sign-in attempt (message-only failures included).
class EmailLoginResult {
  const EmailLoginResult._({
    required this.errorMessage,
    this.retryAfterSeconds,
  });

  final String? errorMessage;
  final int? retryAfterSeconds;

  bool get isSuccess => errorMessage == null;

  factory EmailLoginResult.success() => const EmailLoginResult._(
    errorMessage: null,
  );

  factory EmailLoginResult.failure(
    String message, {
    int? retryAfterSeconds,
  }) => EmailLoginResult._(
    errorMessage: message,
    retryAfterSeconds: retryAfterSeconds,
  );
}
