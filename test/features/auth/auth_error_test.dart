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
}
