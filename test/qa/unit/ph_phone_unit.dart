import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/core/utils/ph_phone.dart';

import '../support/qa_reporter.dart';

void phPhoneUnitTests() {
  qaGroup('PH mobile numbers', () {
    qaUnitTest('normalizePhMobile handles +63, 63, 9xx and 09xx forms', () {
      expect(normalizePhMobile('+63 917 123 4567'), '09171234567');
      expect(normalizePhMobile('639171234567'), '09171234567');
      expect(normalizePhMobile('9171234567'), '09171234567');
      expect(normalizePhMobile('0917-123-4567'), '09171234567');
    });

    qaUnitTest('normalizePhMobile rejects invalid numbers', () {
      expect(normalizePhMobile(null), isNull);
      expect(normalizePhMobile(''), isNull);
      expect(normalizePhMobile('12345'), isNull);
      expect(normalizePhMobile('08171234567'), isNull);
      expect(normalizePhMobile('091712345678'), isNull);
    });

    qaUnitTest('isValidPhMobile mirrors normalizePhMobile', () {
      expect(isValidPhMobile('+639171234567'), isTrue);
      expect(isValidPhMobile('not a phone'), isFalse);
    });

    qaUnitTest('formatPhMobile groups digits as 0917 123 4567', () {
      expect(formatPhMobile('+639171234567'), '0917 123 4567');
      expect(formatPhMobile('  abc  '), 'abc');
      expect(formatPhMobile(null), '');
    });

    qaUnitTest('phMobileValidationError flags empty/invalid input', () {
      const message = 'Please enter a valid phone number.';
      expect(phMobileValidationError(null), message);
      expect(phMobileValidationError('  '), message);
      expect(phMobileValidationError('0917'), message);
      expect(phMobileValidationError('09171234567'), isNull);
    });

    qaUnitTest('isPhMobile09Format requires exactly 11 digits from 09', () {
      expect(isPhMobile09Format('09171234567'), isTrue);
      expect(isPhMobile09Format(' 09171234567 '), isTrue);
      expect(isPhMobile09Format('+639171234567'), isFalse);
      expect(isPhMobile09Format('0917 123 4567'), isFalse);
      expect(isPhMobile09Format(null), isFalse);
    });

    qaUnitTest('phMobile09FormatValidationError messages', () {
      expect(
        phMobile09FormatValidationError(''),
        'Enter a Philippine mobile number.',
      );
      expect(
        phMobile09FormatValidationError('0917'),
        'Enter a valid 11-digit mobile number starting with 09.',
      );
      expect(phMobile09FormatValidationError('09171234567'), isNull);
    });
  });
}
