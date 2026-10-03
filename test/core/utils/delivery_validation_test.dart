import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/core/utils/ph_phone.dart';
import 'package:thriftline/core/utils/validators.dart';

void main() {
  group('Delivery validation tests', () {
    group('Validators.riderName', () {
      test('accepts valid human rider names', () {
        const valid = [
          'Juan Dela Cruz',
          'Maria Clara',
          'Mark-Anthony Santos',
          "O'Connor",
          'José Rizal',
        ];
        for (final name in valid) {
          expect(Validators.riderName(name), isNull, reason: name);
        }
      });

      test('requires non-empty rider name', () {
        expect(Validators.riderName(''), Validators.riderNameRequiredMessage);
        expect(Validators.riderName('   '), Validators.riderNameRequiredMessage);
        expect(Validators.riderName(null), Validators.riderNameRequiredMessage);
      });

      test('rejects numbers and symbols', () {
        const invalid = [
          'Juan123',
          '123456',
          'Rider #1',
          'Mark@Lalamove',
          'Rider 0917',
          'Kuya_Jojo',
          'Rider!',
          'Pedro 🛵',
        ];
        for (final name in invalid) {
          expect(
            Validators.riderName(name),
            Validators.riderNameInvalidMessage,
            reason: name,
          );
        }
      });
    });

    group('phMobileValidationError (general message)', () {
      test('accepts valid Philippine phone numbers', () {
        const valid = [
          '09171234567',
          '+639171234567',
          '639171234567',
          '9171234567',
          '0917 123 4567',
        ];
        for (final phone in valid) {
          expect(phMobileValidationError(phone), isNull, reason: phone);
        }
      });

      test('returns general error message for invalid or empty phone numbers', () {
        const invalid = [
          '',
          '   ',
          '12345',
          '08171234567',
          '0917123456', // only 10 digits
          '091712345678', // 12 digits
          'abcdefghijk',
          null,
        ];
        for (final phone in invalid) {
          expect(
            phMobileValidationError(phone),
            'Please enter a valid phone number.',
            reason: phone.toString(),
          );
        }
      });
    });
  });
}
