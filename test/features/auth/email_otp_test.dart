import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thriftline/core/constants/app_constants.dart';
import 'package:thriftline/core/services/shared_preferences_service.dart';
import 'package:thriftline/core/services/supabase_service.dart';
import 'package:thriftline/features/auth/data/auth_result.dart';
import 'package:thriftline/features/auth/data/auth_service.dart';
import 'package:thriftline/providers/auth_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('authIsFullyAuthenticated', () {
    test('is false without a session', () {
      expect(
        authIsFullyAuthenticated(hasSession: false, emailOtpPending: false),
        isFalse,
      );
    });

    test('is false while email OTP is still pending', () {
      expect(
        authIsFullyAuthenticated(hasSession: true, emailOtpPending: true),
        isFalse,
      );
    });

    test('is true only after a session and a completed OTP', () {
      expect(
        authIsFullyAuthenticated(hasSession: true, emailOtpPending: false),
        isTrue,
      );
    });
  });

  group('AuthResult email OTP', () {
    test('marks email/password success as requiring OTP', () {
      final result = AuthResult.success(null, requiresEmailOtp: true);

      expect(result.success, isTrue);
      expect(result.requiresEmailOtp, isTrue);
      expect(result.requiresEmailVerification, isFalse);
    });

    test('does not require OTP on a Google-style success', () {
      final result = AuthResult.success(null);

      expect(result.success, isTrue);
      expect(result.requiresEmailOtp, isFalse);
    });
  });

  group('email OTP pending flag', () {
    test('persists and is cleared with the auth session', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferencesService.init();

      expect(prefs.isEmailOtpPending, isFalse);

      await prefs.setEmailOtpPending(true);
      expect(prefs.isEmailOtpPending, isTrue);

      await prefs.clearAuthSession();
      expect(prefs.isEmailOtpPending, isFalse);
    });

    test('AuthProvider starts not pending and not fully authenticated', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferencesService.init();
      final auth = AuthProvider(prefs, AuthService(SupabaseService()));

      expect(auth.isEmailOtpPending, isFalse);
      expect(auth.isAuthenticated, isFalse);
      expect(auth.isFullyAuthenticated, isFalse);
    });

    test('restored pending flag matches the SharedPreferences key', () async {
      SharedPreferences.setMockInitialValues({
        AppConstants.keyEmailOtpPending: true,
      });
      final prefs = await SharedPreferencesService.init();

      expect(prefs.isEmailOtpPending, isTrue);
    });
  });
}
