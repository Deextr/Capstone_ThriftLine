import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/buyer/domain/looking_for_lifecycle.dart';

void main() {
  group('lookingForRequestTitleError', () {
    test('rejects empty title', () {
      expect(
        lookingForRequestTitleError(''),
        lookingForRequestTitleTooShortMessage,
      );
      expect(
        lookingForRequestTitleError('   '),
        lookingForRequestTitleTooShortMessage,
      );
    });

    test('rejects titles shorter than 5 characters', () {
      expect(
        lookingForRequestTitleError('abc'),
        lookingForRequestTitleTooShortMessage,
      );
      expect(
        lookingForRequestTitleError('abcd'),
        lookingForRequestTitleTooShortMessage,
      );
    });

    test('accepts titles from 5 through 100 characters', () {
      expect(lookingForRequestTitleError('abcde'), isNull);
      expect(lookingForRequestTitleError('a' * 10), isNull);
      expect(lookingForRequestTitleError('a' * 99), isNull);
      expect(lookingForRequestTitleError('a' * 100), isNull);
    });

    test('rejects titles longer than 100 characters', () {
      expect(
        lookingForRequestTitleError('a' * 101),
        lookingForRequestTitleTooLongMessage,
      );
    });

    test('uses trimmed length for boundary checks', () {
      expect(lookingForRequestTitleError('  ab  '), isNotNull);
      expect(lookingForRequestTitleError('  ${'a' * 5}  '), isNull);
    });
  });
}
