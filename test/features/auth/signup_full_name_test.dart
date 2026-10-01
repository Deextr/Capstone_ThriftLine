import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/core/utils/validators.dart';

void main() {
  group('Validators.name (signup full name)', () {
    test('accepts common valid names', () {
      const valid = [
        'Juan Dela Cruz',
        'Maria Clara',
        'Anne-Marie Reyes',
        "O'Connor",
        'José García',
        'François Müller',
      ];
      for (final name in valid) {
        expect(Validators.name(name), isNull, reason: name);
      }
    });

    test('requires a non-empty name', () {
      expect(Validators.name(''), Validators.fullNameRequiredMessage);
      expect(Validators.name('   '), Validators.fullNameRequiredMessage);
    });

    test('rejects numbers and invalid characters', () {
      const invalid = [
        'Juan123',
        '123456',
        'Maria@123',
        'An4 Dela Cruz',
        'Maria 😀',
      ];
      for (final name in invalid) {
        expect(
          Validators.name(name),
          Validators.fullNameInvalidMessage,
          reason: name,
        );
      }
    });

    test('normalizeFullName trims and collapses spaces', () {
      expect(
        Validators.normalizeFullName('  Juan   Dela   Cruz  '),
        'Juan Dela Cruz',
      );
    });
  });
}
