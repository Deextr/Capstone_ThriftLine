import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/core/utils/ph_phone.dart';
import 'package:thriftline/features/auth/domain/auth_user.dart';
import 'package:thriftline/features/auth/domain/phone_otp.dart';
import 'package:thriftline/models/enums.dart';

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
    test('maps phone_already_in_use to privacy-safe copy', () {
      const result = PhoneOtpResult.failure(
        'ignored',
        code: PhoneOtpErrorCode.phoneAlreadyInUse,
      );
      expect(phoneOtpUserMessage(result), kPhoneAlreadyInUseMessage);
      expect(kPhoneAlreadyInUseMessage, contains('already in use'));
      expect(kPhoneAlreadyInUseMessage.toLowerCase(), isNot(contains('email')));
    });

    test('treats network_unavailable as unsupported carrier UI', () {
      const result = PhoneOtpResult.failure(
        kSmsNetworkUnavailableMessage,
        code: PhoneOtpErrorCode.networkUnavailable,
      );
      expect(result.isOk, isFalse);
      expect(result.isSmsNetworkUnavailable, isTrue);
    });

    test('legacy dito_unavailable maps to the same UI', () {
      const result = PhoneOtpResult.failure(
        kSmsNetworkUnavailableMessage,
        code: PhoneOtpErrorCode.ditoUnavailable,
      );
      expect(result.isSmsNetworkUnavailable, isTrue);
    });

    test('success has no user-facing error', () {
      const result = PhoneOtpResult.success(retryAfterSeconds: 60);
      expect(result.isOk, isTrue);
      expect(result.retryAfterSeconds, 60);
    });

    test('maps invalid_code to buyer-friendly copy', () {
      const result = PhoneOtpResult.failure(
        'raw',
        code: PhoneOtpErrorCode.invalidCode,
      );
      expect(
        phoneOtpUserMessage(result),
        'The verification code is incorrect.',
      );
    });
  });

  group('edit profile phone validation', () {
    test('accepts Globe and TM numbers in local 09 form', () {
      expect(phMobile09EditProfileValidationError('09171234567'), isNull);
      expect(phMobile09EditProfileValidationError('09051234567'), isNull);
      expect(phMobile09EditProfileValidationError('09151234567'), isNull);
    });

    test('accepts +63 and spaced forms before the 09 rule', () {
      expect(phMobile09EditProfileValidationError('+639171234567'), isNull);
      expect(phMobile09EditProfileValidationError('639171234567'), isNull);
      expect(phMobile09EditProfileValidationError('0917 123 4567'), isNull);
      expect(collapsePhMobileFieldText('+639171234567'), '09171234567');
      expect(collapsePhMobileFieldText('639171234567'), '09171234567');
      expect(
        collapsePhMobileFieldText('6391712345678', previous: '09171234567'),
        '09171234567',
      );
    });

    test('rejects overlong paste safely', () {
      expect(
        phMobile09EditProfileValidationError('12093129032193'),
        'Phone number must contain exactly 11 digits.',
      );
    });

    test(
      'rejects short numbers, letters, and numbers that do not start with 09',
      () {
        expect(
          phMobile09EditProfileValidationError('0917123456'),
          'Phone number must contain exactly 11 digits.',
        );
        expect(
          phMobile09EditProfileValidationError('0917abc4567'),
          'Phone number must contain exactly 11 digits.',
        );
        expect(
          phMobile09EditProfileValidationError('08171234567'),
          'Enter a valid 11-digit Philippine mobile number starting with 09.',
        );
      },
    );

    test('does not treat a truncated +63 value as a finished 09 number', () {
      expect(normalizePhMobile('63917123456'), isNull);
      expect(
        phMobile09EditProfileValidationError('63917123456'),
        'Phone number must contain exactly 11 digits.',
      );
    });
  });

  group('SMS delivery errors stay separate from format errors', () {
    test(
      'provider credit and auth failures are not shown as an invalid number',
      () {
        const credits = PhoneOtpResult.failure(
          'Insufficient sms credits',
          code: PhoneOtpErrorCode.providerCredits,
        );
        const auth = PhoneOtpResult.failure(
          '{"error":"invalid api key"}',
          code: PhoneOtpErrorCode.providerAuth,
        );
        expect(phoneOtpUserMessage(credits), kSmsDeliveryUnavailableMessage);
        expect(phoneOtpUserMessage(auth), kSmsDeliveryUnavailableMessage);
        expect(
          phoneOtpUserMessage(credits),
          isNot(contains('Enter a valid 11-digit Philippine mobile number')),
        );
      },
    );
  });

  group('AuthUser.hasVerifiedAccountPhone', () {
    const base = AuthUser(
      id: 'u1',
      username: 'buyer',
      name: 'Buyer',
      email: 'b@test.com',
      role: UserRole.buyer,
      avatarUrl: '',
      location: '',
    );

    test('is true only when verified with valid 09 number', () {
      expect(
        base
            .copyWith(isPhoneVerified: true, phone: '09171234567')
            .hasVerifiedAccountPhone,
        isTrue,
      );
      expect(
        base
            .copyWith(isPhoneVerified: false, phone: '09171234567')
            .hasVerifiedAccountPhone,
        isFalse,
      );
      expect(
        base
            .copyWith(isPhoneVerified: true, phone: '08171234567')
            .hasVerifiedAccountPhone,
        isFalse,
      );
    });
  });
}
