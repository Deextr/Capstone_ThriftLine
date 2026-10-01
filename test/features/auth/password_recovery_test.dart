import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/core/routes/auth_redirect.dart';
import 'package:thriftline/core/routes/route_names.dart';
import 'package:thriftline/core/utils/validators.dart';
import 'package:thriftline/features/auth/data/password_recovery_link.dart';
import 'package:thriftline/features/buyer/data/paymongo_return_link.dart';

void main() {
  group('PasswordRecoveryLink', () {
    test('reads the recovery token hash from the app deep link', () {
      final uri = Uri.parse(
        '${PasswordRecoveryLink.redirectUrl}?token_hash=abc123&type=recovery',
      );
      expect(PasswordRecoveryLink.recoveryTokenHash(uri), 'abc123');
      expect(
        PasswordRecoveryLink.recoveryTokenHash(
          Uri.parse('${PasswordRecoveryLink.redirectUrl}#access_token=1'),
        ),
        isNull,
      );
    });

    test('recognizes the app reset-password deep link', () {
      final uri = Uri.parse(
        '${PasswordRecoveryLink.redirectUrl}?code=test-code',
      );
      expect(PasswordRecoveryLink.isRecoveryUri(uri), isTrue);
    });

    test('does not treat PayMongo return links as recovery', () {
      final uri = Uri.parse(
        '$kPaymongoAppScheme://$kPaymongoReturnHost?status=success&order_id=11111111-1111-4111-8111-111111111111',
      );
      expect(PasswordRecoveryLink.isRecoveryUri(uri), isFalse);
    });
  });

  group('password recovery routing', () {
    test('allows forgot and reset routes as public auth paths', () {
      expect(isPublicAuthRoute(RouteNames.forgotPassword), isTrue);
      expect(isPublicAuthRoute(RouteNames.resetPassword), isTrue);
      expect(isPublicAuthRoute(RouteNames.login), isTrue);
      expect(isPublicAuthRoute(RouteNames.buyerHome), isFalse);
    });

    test('forces reset screen while recovery session is active', () {
      expect(
        passwordRecoveryWorkspaceRedirect(
          recoveryActive: true,
          location: RouteNames.login,
        ),
        RouteNames.resetPassword,
      );
      expect(
        passwordRecoveryWorkspaceRedirect(
          recoveryActive: true,
          location: RouteNames.resetPassword,
        ),
        isNull,
      );
    });
  });

  group('Validators password recovery', () {
    test('email rejects invalid formats', () {
      expect(Validators.email('not-an-email'), isNotNull);
      expect(Validators.email('user@example.com'), isNull);
    });

    test('password enforces minimum length', () {
      expect(Validators.password('12345'), isNotNull);
      expect(Validators.password('123456'), isNull);
    });

    test('confirmPassword requires a match', () {
      expect(Validators.confirmPassword('abc', 'xyz'), isNotNull);
      expect(Validators.confirmPassword('abc', 'abc'), isNull);
    });
  });
}
