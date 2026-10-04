import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/core/utils/validators.dart';

import '../support/qa_reporter.dart';

void validatorsUnitTests() {
  qaGroup('Validators', () {
    qaGroup('email', () {
      qaUnitTest('rejects null and blank input', () {
        expect(Validators.email(null), 'Please enter your email address.');
        expect(Validators.email('   '), 'Please enter your email address.');
      });

      qaUnitTest('rejects malformed addresses', () {
        const invalid = 'Please enter a valid email address.';
        expect(Validators.email('buyer@thriftline'), invalid);
        expect(Validators.email('buyer.thriftline.ph'), invalid);
        expect(Validators.email('buy er@thriftline.ph'), invalid);
        expect(Validators.email('a@@b.com'), invalid);
      });

      qaUnitTest('accepts a valid address with surrounding spaces', () {
        expect(Validators.email('  dexter@thriftline.ph '), isNull);
      });
    });

    qaGroup('username', () {
      qaUnitTest('requires a value', () {
        expect(Validators.username(''), 'Username is required');
        expect(Validators.username(null), 'Username is required');
      });

      qaUnitTest('enforces a 3 character minimum', () {
        expect(
          Validators.username('ab'),
          'Username must be at least 3 characters',
        );
      });

      qaUnitTest('only allows letters, numbers and underscores', () {
        expect(
          Validators.username('dex-ter'),
          'Username can only contain letters, numbers, and underscores',
        );
        expect(Validators.username('dex_ter99'), isNull);
      });
    });

    qaGroup('full name', () {
      qaUnitTest('requires a value', () {
        expect(Validators.name(null), Validators.fullNameRequiredMessage);
        expect(Validators.name('   '), Validators.fullNameRequiredMessage);
      });

      qaUnitTest('accepts hyphens, apostrophes and accented letters', () {
        expect(Validators.name('Juan Dela Cruz'), isNull);
        expect(Validators.name("Mary-Ann O'Neil"), isNull);
        expect(Validators.name('José Rizal'), isNull);
        expect(Validators.name('  Juan   Dela  Cruz '), isNull);
      });

      qaUnitTest('rejects digits, symbols and dangling punctuation', () {
        expect(Validators.name('John3'), Validators.fullNameInvalidMessage);
        expect(Validators.name('Juan@Cruz'), Validators.fullNameInvalidMessage);
        expect(Validators.name('-Juan'), Validators.fullNameInvalidMessage);
        expect(Validators.name("Juan'"), Validators.fullNameInvalidMessage);
      });

      qaUnitTest('normalizeFullName trims and collapses spaces', () {
        expect(
          Validators.normalizeFullName('  Juan   Dela  Cruz '),
          'Juan Dela Cruz',
        );
      });

      qaUnitTest('input filter allows letters but not digits/symbols', () {
        expect(Validators.fullNameInputCharacters.hasMatch('a'), isTrue);
        expect(Validators.fullNameInputCharacters.hasMatch('ñ'), isTrue);
        expect(Validators.fullNameInputCharacters.hasMatch('-'), isTrue);
        expect(Validators.fullNameInputCharacters.hasMatch('1'), isFalse);
        expect(Validators.fullNameInputCharacters.hasMatch('@'), isFalse);
      });
    });

    qaGroup('rider name', () {
      qaUnitTest('uses rider specific messages', () {
        expect(Validators.riderName(''), Validators.riderNameRequiredMessage);
        expect(
          Validators.riderName('R1der'),
          Validators.riderNameInvalidMessage,
        );
        expect(Validators.riderName('Pedro Santos'), isNull);
      });
    });

    qaGroup('password', () {
      qaUnitTest('requires at least 6 characters', () {
        expect(Validators.password(null), 'Please enter a password.');
        expect(Validators.password(''), 'Please enter a password.');
        expect(
          Validators.password('12345'),
          'Password must be at least 6 characters.',
        );
        expect(Validators.password('123456'), isNull);
      });

      qaUnitTest('confirmPassword must match the original', () {
        expect(
          Validators.confirmPassword('', 'secret1'),
          'Please confirm your password.',
        );
        expect(
          Validators.confirmPassword('secret2', 'secret1'),
          'Passwords do not match.',
        );
        expect(Validators.confirmPassword('secret1', 'secret1'), isNull);
      });
    });
  });
}
