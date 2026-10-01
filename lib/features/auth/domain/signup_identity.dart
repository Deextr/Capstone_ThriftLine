/// How a GoTrue `signUp` response should be treated for ThriftLine.
///
/// One email maps to one account. A Google identity on the returned user means
/// this was not a new email/password registration — GoTrue either echoed the
/// existing user or tried to attach a password to it.
enum SignupOutcome {
  /// New email/password signup (or confirm-email pending). Safe to continue.
  proceed,

  /// Classic GoTrue placeholder: no session and no identities.
  alreadyRegistered,

  /// The auth user already has a Google (or other OAuth) identity.
  existingGoogleAccount,
}

/// Classifies identities from a sign-up response. Does not call the network.
SignupOutcome classifySignupIdentities({
  required bool hasSession,
  required Iterable<String> providers,
}) {
  final normalized = providers
      .map((p) => p.trim().toLowerCase())
      .where((p) => p.isNotEmpty)
      .toSet();

  if (normalized.any((p) => p != 'email')) {
    return SignupOutcome.existingGoogleAccount;
  }
  if (!hasSession && normalized.isEmpty) {
    return SignupOutcome.alreadyRegistered;
  }
  return SignupOutcome.proceed;
}

/// User-facing copy when signup must stop. Names Google only when that
/// identity was present on the Auth response — not from a public.users lookup.
String existingAccountSignupMessage(SignupOutcome outcome) {
  return switch (outcome) {
    SignupOutcome.existingGoogleAccount =>
      'An account with this email already exists. '
          'Please continue with Google to sign in.',
    SignupOutcome.alreadyRegistered =>
      'An account with this email already exists. '
          'Please sign in with the method you used to create it.',
    SignupOutcome.proceed =>
      'An account with this email already exists. '
          'Please sign in with the method you used to create it.',
  };
}

/// User-facing copy when Google sign-in is blocked because the email
/// already belongs to an email/password account.
const existingEmailPasswordAccountMessage =
    'An account with this email already exists. '
    'Please sign in with your email and password.';
