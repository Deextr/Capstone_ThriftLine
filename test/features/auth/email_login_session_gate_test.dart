import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/auth/data/auth_result.dart';
import 'package:thriftline/providers/auth_provider.dart';

bool emailOtpRequiredFromEdgeBody(Map<String, dynamic> data) {
  final emailOtp = data['email_otp'];
  if (emailOtp is! Map) return true;
  final required = emailOtp['required'];
  if (required is bool) return required;
  return true;
}

void main() {
  group('email login session gate edge payload', () {
    test('requires OTP when gate is pending', () {
      expect(
        emailOtpRequiredFromEdgeBody(const {
          'session': {},
          'email_otp': {'required': true, 'skipped_trusted_device': false},
        }),
        isTrue,
      );
    });

    test('skips OTP when server trusted device registered the gate', () {
      expect(
        emailOtpRequiredFromEdgeBody(const {
          'session': {},
          'email_otp': {'required': false, 'skipped_trusted_device': true},
        }),
        isFalse,
      );
    });

    test('AuthResult reflects server OTP requirement flag', () {
      final pending = AuthResult.success(null, requiresEmailOtp: true);
      final trusted = AuthResult.success(null, requiresEmailOtp: false);

      expect(pending.requiresEmailOtp, isTrue);
      expect(trusted.requiresEmailOtp, isFalse);
    });
  });

  group('shouldReopenEmailOtpFromAccessProbe', () {
    test('does not reopen OTP after a successful verify', () {
      expect(
        shouldReopenEmailOtpFromAccessProbe(
          verifyJustSucceeded: true,
          serverAccessGranted: false,
        ),
        isFalse,
      );
    });

    test('does not reopen OTP when the server already granted access', () {
      expect(
        shouldReopenEmailOtpFromAccessProbe(
          verifyJustSucceeded: false,
          serverAccessGranted: true,
        ),
        isFalse,
      );
    });
  });
}
