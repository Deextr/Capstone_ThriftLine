import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/providers/auth_provider.dart';

void main() {
  group('Authentication state', () {
    test('AUTH-004 logged-out user has no authenticated session', () {
      expect(
        authIsFullyAuthenticated(
          hasSession: false,
          emailOtpPending: false,
        ),
        isFalse,
      );
    });

    test('AUTH-004 pending OTP is not a fully authenticated session', () {
      expect(
        authIsFullyAuthenticated(
          hasSession: true,
          emailOtpPending: true,
        ),
        isFalse,
      );
    });

    test('AUTH-005 authenticated user has a valid session', () {
      expect(
        authIsFullyAuthenticated(
          hasSession: true,
          emailOtpPending: false,
        ),
        isTrue,
      );
    });
  });
}

// AUTH-001, AUTH-002, and AUTH-003 call Supabase and belong in an integration
// test suite with a dedicated test project or seeded test users. They should
// verify the AuthResult returned by AuthService.signInWithEmail(), not hardcode
// production credentials in this unit-test suite.
