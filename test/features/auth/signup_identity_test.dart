import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/auth/domain/signup_identity.dart';

void main() {
  group('classifySignupIdentities', () {
    test('Scenario C: new email signup with only email identity proceeds', () {
      expect(
        classifySignupIdentities(
          hasSession: true,
          providers: const ['email'],
        ),
        SignupOutcome.proceed,
      );
    });

    test('Scenario C: confirm-email pending (no session, email identity) proceeds', () {
      expect(
        classifySignupIdentities(
          hasSession: false,
          providers: const ['email'],
        ),
        SignupOutcome.proceed,
      );
    });

    test('Scenario E: unverified email retry still looks like email-only', () {
      expect(
        classifySignupIdentities(
          hasSession: false,
          providers: const ['email'],
        ),
        SignupOutcome.proceed,
      );
    });

    test('Scenario A: Google account then email signup is rejected', () {
      expect(
        classifySignupIdentities(
          hasSession: true,
          providers: const ['google', 'email'],
        ),
        SignupOutcome.existingGoogleAccount,
      );
      expect(
        classifySignupIdentities(
          hasSession: false,
          providers: const ['google'],
        ),
        SignupOutcome.existingGoogleAccount,
      );
    });

    test('GoTrue placeholder for an existing confirmed email is rejected', () {
      expect(
        classifySignupIdentities(hasSession: false, providers: const []),
        SignupOutcome.alreadyRegistered,
      );
    });

    test('Scenario D: a different provider list is not inferred from empty data', () {
      expect(
        classifySignupIdentities(hasSession: true, providers: const ['email']),
        isNot(SignupOutcome.existingGoogleAccount),
      );
    });

    test('provider names are matched case-insensitively', () {
      expect(
        classifySignupIdentities(
          hasSession: true,
          providers: const ['Google'],
        ),
        SignupOutcome.existingGoogleAccount,
      );
    });
  });

  group('existing account messages', () {
    test('names Google only when that identity was on the Auth response', () {
      expect(
        existingAccountSignupMessage(SignupOutcome.existingGoogleAccount),
        'This email is already associated with an existing ThriftLine account. '
        'Please sign in using Google.',
      );
      expect(
        existingAccountSignupMessage(SignupOutcome.alreadyRegistered),
        'This email is already associated with an existing ThriftLine account. '
        'Please log in instead.',
      );
    });

    test('Scenario B: Google login against an email account points at password login', () {
      expect(
        existingEmailPasswordAccountMessage,
        contains('email and password'),
      );
    });
  });
}
