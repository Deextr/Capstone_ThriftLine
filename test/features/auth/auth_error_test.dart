import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/auth/domain/auth_error.dart';

void main() {
  group('parseGoTrueError', () {
    test('unwraps nested JSON from a GoTrue 500', () {
      const raw =
          '{"code":"unexpected_failure","message":"Error creating identity"}';
      final parsed = parseGoTrueError(code: null, message: raw);

      expect(parsed.code, 'unexpected_failure');
      expect(parsed.message, 'Error creating identity');
    });

    test('keeps a normal AuthException as-is', () {
      final parsed = parseGoTrueError(
        code: 'invalid_credentials',
        message: 'Invalid login credentials',
      );
      expect(parsed.code, 'invalid_credentials');
      expect(parsed.message, 'Invalid login credentials');
    });
  });

  group('isExistingAccountAuthError', () {
    test('treats Error creating identity as an account conflict', () {
      expect(
        isExistingAccountAuthError(
          parseGoTrueError(
            code: '-',
            message:
                '{"code":"unexpected_failure","message":"Error creating identity"}',
          ),
        ),
        isTrue,
      );
    });
  });

  group('isOauthAccountSignupBlocked', () {
    test('recognizes the identity trigger and GoTrue identity error', () {
      expect(
        isOauthAccountSignupBlocked(
          parseGoTrueError(
            code: null,
            message:
                '{"code":"unexpected_failure","message":"Error creating identity"}',
          ),
        ),
        isTrue,
      );
      expect(
        isOauthAccountSignupBlocked(
          parseGoTrueError(
            code: '23505',
            message: 'An account with this email already exists',
          ),
        ),
        isTrue,
      );
    });

    test('does not treat a generic existing-user error as Google', () {
      expect(
        isOauthAccountSignupBlocked(
          parseGoTrueError(
            code: 'user_already_exists',
            message: 'User already registered',
          ),
        ),
        isFalse,
      );
    });
  });

  group('parseEdgeFunctionError', () {
    test('reads error and code from JSON maps and strings', () {
      expect(
        parseEdgeFunctionError({
          'error': 'Invalid email or password. Please try again.',
          'code': 'invalid_credentials',
        }).message,
        'Invalid email or password. Please try again.',
      );
      expect(
        parseEdgeFunctionError(
          '{"message":"Invalid login credentials","code":"invalid_credentials"}',
        ).code,
        'invalid_credentials',
      );
    });
  });

  group('emailLoginUiMessage', () {
    test('maps edge function codes to safe copy', () {
      expect(
        emailLoginUiMessage(code: 'invalid_credentials'),
        emailLoginIncorrectCredentialsMessage,
      );
      expect(
        emailLoginUiMessage(httpStatus: 401, serverError: 'Unauthorized'),
        emailLoginIncorrectCredentialsMessage,
      );
      expect(
        emailLoginUiMessage(
          httpStatus: 0,
          serverError: 'ClientException: Failed to fetch, uri=https://example.com',
        ),
        emailLoginNetworkMessage,
      );
      expect(
        isEmailLoginTransportFailure(
          httpStatus: 0,
          message: 'ClientException: Failed to fetch',
        ),
        isTrue,
      );
      expect(
        isEmailLoginTransportFailure(
          httpStatus: 401,
          errorCode: 'invalid_credentials',
        ),
        isFalse,
      );
      expect(
        adminLoginLockoutMessage(272),
        contains('4:32'),
      );
      expect(
        emailLoginUiMessage(code: 'turnstile_failed'),
        'Human verification failed. Please try again.',
      );
      expect(
        emailLoginUiMessage(
          code: 'turnstile_failed',
          serverError: 'Verification expired. Complete the check again.',
        ),
        'Verification expired. Complete the check again.',
      );
      expect(
        emailLoginUiMessage(code: 'rate_limited'),
        emailLoginRateLimitMessage,
      );
      expect(
        adminLoginInvalidCredentialsMessage(3),
        'Incorrect email or password.\n3 attempts remaining.',
      );
      expect(
        emailLoginUiMessage(
          code: 'invalid_credentials',
          errorBody: {
            'code': 'invalid_credentials',
            'attempts_remaining': 2,
            'failed_attempts': 3,
            'max_attempts': 5,
          },
        ),
        adminLoginInvalidCredentialsMessage(2),
      );
      expect(
        emailLoginUiMessage(
          code: 'unavailable',
          httpStatus: 401,
          serverError: 'Sign-in is temporarily unavailable. Please try again.',
        ),
        emailLoginIncorrectCredentialsMessage,
      );
    });
  });

  group('passwordResetUiMessage', () {
    test(
      'keeps rate-limit and validation copy and hides other server text',
      () {
        expect(
          passwordResetUiMessage(
            'Too many reset emails requested. Please wait.',
          ),
          contains('Too many reset emails'),
        );
        expect(
          passwordResetUiMessage('Enter a valid email address.'),
          'Enter a valid email address.',
        );
        expect(
          passwordResetUiMessage('smtp auth failed for user secret'),
          'We could not send the reset email right now. '
          'Please try again in a moment.',
        );
      },
    );
  });
}
