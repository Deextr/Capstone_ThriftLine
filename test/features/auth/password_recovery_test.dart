import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/core/routes/auth_redirect.dart';
import 'package:thriftline/core/routes/route_names.dart';
import 'package:thriftline/core/utils/validators.dart';
import 'package:thriftline/features/auth/data/password_recovery_link.dart';
import 'package:thriftline/features/buyer/data/paymongo_return_link.dart';
import 'package:thriftline/providers/auth_provider.dart';

void main() {
  group('PasswordRecoveryLink', () {
    test('merges fragment tokens into query for Android intents', () {
      final uri = Uri.parse(
        'thriftline://reset-password#access_token=abc&type=recovery',
      );
      final normalized = PasswordRecoveryLink.normalizeCallbackUri(uri);
      expect(normalized.queryParameters['access_token'], 'abc');
      expect(normalized.queryParameters['type'], 'recovery');
      expect(normalized.fragment, isEmpty);
    });

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

    test('recognizes the Storage open page as a recovery link', () {
      final uri = Uri.parse(
        'https://zakorrcmmswwzfihmcji.supabase.co/storage/v1/object/public/'
        'app-links/open-thriftline.html?token_hash=abc123&type=recovery',
      );
      expect(PasswordRecoveryLink.isRecoveryUri(uri), isTrue);
      expect(PasswordRecoveryLink.recoveryTokenHash(uri), 'abc123');
    });

    test('recognizes the HTTPS bounce URL as a recovery link', () {
      final uri = Uri.parse(
        'https://zakorrcmmswwzfihmcji.supabase.co/functions/v1/'
        'password-recovery-return?token_hash=abc123&type=recovery',
      );
      expect(PasswordRecoveryLink.isRecoveryUri(uri), isTrue);
      expect(PasswordRecoveryLink.recoveryTokenHash(uri), 'abc123');
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

  group('password recovery session lifecycle', () {
    test('does not persist normal login cache during recovery', () {
      expect(
        shouldPersistAuthSession(
          passwordRecoveryActive: true,
          passwordRecoveryPending: false,
        ),
        isFalse,
      );
      expect(
        shouldPersistAuthSession(
          passwordRecoveryActive: false,
          passwordRecoveryPending: true,
        ),
        isFalse,
      );
      expect(
        shouldPersistAuthSession(
          passwordRecoveryActive: false,
          passwordRecoveryPending: false,
        ),
        isTrue,
      );
    });

    test('cold start discards abandoned recovery when flag is set', () {
      expect(
        shouldDiscardRecoverySessionOnStartup(passwordRecoveryPending: true),
        isTrue,
      );
      expect(
        shouldDiscardRecoverySessionOnStartup(passwordRecoveryPending: false),
        isFalse,
      );
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
