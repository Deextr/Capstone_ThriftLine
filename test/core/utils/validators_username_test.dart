import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/core/utils/validators.dart';

void main() {
  group('Validators.username', () {
    test('rejects empty and whitespace-only input', () {
      expect(Validators.username(null), Validators.usernameRequiredMessage);
      expect(Validators.username(''), Validators.usernameRequiredMessage);
      expect(Validators.username('   '), Validators.usernameRequiredMessage);
    });

    test('rejects usernames shorter than minimum length', () {
      expect(Validators.username('a'), Validators.usernameTooShortMessage);
      expect(Validators.username('ab'), Validators.usernameTooShortMessage);
      expect(Validators.username(' a '), Validators.usernameTooShortMessage);
    });

    test('accepts minimum-length and longer valid usernames', () {
      expect(Validators.username('abc'), isNull);
      expect(Validators.username('john123'), isNull);
      expect(Validators.username('user_name'), isNull);
    });

    test('rejects invalid characters', () {
      expect(
        Validators.username('abc def'),
        Validators.usernameUnderscoreInvalidMessage,
      );
      expect(
        Validators.username('john@123'),
        Validators.usernameUnderscoreInvalidMessage,
      );
    });
  });

  group('Validators.usernameAlphanumeric (buyer edit profile)', () {
    test('rejects usernames shorter than minimum length', () {
      expect(
        Validators.usernameAlphanumeric('a'),
        Validators.usernameTooShortMessage,
      );
      expect(
        Validators.usernameAlphanumeric('ab'),
        Validators.usernameTooShortMessage,
      );
    });

    test('accepts three or more alphanumeric characters', () {
      expect(Validators.usernameAlphanumeric('abc'), isNull);
      expect(Validators.usernameAlphanumeric('john123'), isNull);
    });

    test('rejects underscores and other special characters', () {
      expect(
        Validators.usernameAlphanumeric('john_smith'),
        Validators.usernameAlphanumericInvalidMessage,
      );
    });
  });
}
