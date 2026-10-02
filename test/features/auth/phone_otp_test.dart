import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/core/utils/ph_phone.dart';
import 'package:thriftline/features/auth/domain/phone_otp.dart';

void main() {
  group('phone OTP UI number rules', () {
    test('accepts exactly 11 digits starting with 09', () {
      expect(isPhMobile09Format('09171234567'), isTrue);
      expect(phMobile09FormatValidationError('09171234567'), isNull);
    });

    test('rejects letters, symbols, and short values', () {
      expect(isPhMobile09Format('0917abc4567'), isFalse);
      expect(isPhMobile09Format('0917-123-4567'), isFalse);
      expect(isPhMobile09Format('9171234567'), isFalse);
      expect(isPhMobile09Format('08171234567'), isFalse);
      expect(phMobile09FormatValidationError(''), isNotNull);
    });

    test('backend still normalizes +63 for sending', () {
      expect(normalizePhMobile('+639171234567'), '09171234567');
      expect(normalizePhMobile('639171234567'), '09171234567');
    });
  });

  group('maskPhMobileForOtp', () {
    test('hides the middle digits after send', () {
      expect(maskPhMobileForOtp('09171234567'), '09••• ••••567');
      expect(maskPhMobileForOtp('+639171234567'), '09••• ••••567');
    });
  });

  group('PhoneOtpResult', () {
    test('treats a DITO provider code as unavailable', () {
      const result = PhoneOtpResult.failure(
        kDitoUnavailableMessage,
        code: PhoneOtpErrorCode.ditoUnavailable,
      );
      expect(result.isOk, isFalse);
      expect(result.isDitoUnavailable, isTrue);
    });

    test('success has no user-facing error', () {
      const result = PhoneOtpResult.success(retryAfterSeconds: 60);
      expect(result.isOk, isTrue);
      expect(result.retryAfterSeconds, 60);
    });
  });
}
