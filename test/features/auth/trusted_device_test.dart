import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thriftline/core/constants/app_constants.dart';
import 'package:thriftline/core/routes/auth_redirect.dart';
import 'package:thriftline/core/routes/route_names.dart';
import 'package:thriftline/core/services/shared_preferences_service.dart';
import 'package:thriftline/features/auth/data/trusted_device_store.dart';
import 'package:thriftline/features/auth/domain/trusted_device.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('shouldSkipEmailOtp', () {
    test(
      'skips only when the password succeeded and the server granted trust',
      () {
        expect(
          shouldSkipEmailOtp(passwordAccepted: true, serverTrusted: true),
          isTrue,
        );
      },
    );

    test('does not skip when the password was rejected', () {
      expect(
        shouldSkipEmailOtp(passwordAccepted: false, serverTrusted: true),
        isFalse,
      );
    });

    test('does not skip when the server did not grant trust', () {
      expect(
        shouldSkipEmailOtp(passwordAccepted: true, serverTrusted: false),
        isFalse,
      );
    });
  });

  group('showEmailTrustedDeviceLogout', () {
    test('is only for email/password identities, not Google Sign-In', () {
      expect(showEmailTrustedDeviceLogout(usesEmailPasswordAuth: true), isTrue);
      expect(
        showEmailTrustedDeviceLogout(usesEmailPasswordAuth: false),
        isFalse,
      );
    });
  });

  group('device trust token', () {
    test('accepts a 32-byte lowercase hex token', () {
      final token = generateDeviceTrustToken();
      expect(token, hasLength(64));
      expect(isDeviceTrustToken(token), isTrue);
    });

    test('rejects short, empty, and uppercase values', () {
      expect(isDeviceTrustToken(''), isFalse);
      expect(isDeviceTrustToken('abc'), isFalse);
      expect(isDeviceTrustToken('A' * 64), isFalse);
    });

    test('labels only the platform, never a device name', () {
      expect(trustedDevicePlatformLabel(TargetPlatform.android), 'android');
      expect(trustedDevicePlatformLabel(TargetPlatform.iOS), 'ios');
      expect(trustedDevicePlatformLabel(TargetPlatform.windows), 'other');
    });
  });

  group('TrustedDeviceStore', () {
    late SharedPreferencesService prefs;
    late MemorySecureKeyValueStore secure;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferencesService.init();
      secure = MemorySecureKeyValueStore();
    });

    test(
      'keeps one token for this install and does not put it in preferences',
      () async {
        final store = TrustedDeviceStore(prefs, secure: secure);

        final first = await store.currentToken();
        final second = await store.currentToken();

        expect(second, first);
        expect(prefs.deviceTrustInstallId, isNot(first));
        expect(prefs.deviceTrustInstallId, isNotNull);
        expect(
          secure.values.values.where((value) => value == first),
          hasLength(1),
        );
      },
    );

    test('survives a normal logout', () async {
      final store = TrustedDeviceStore(prefs, secure: secure);
      final token = await store.currentToken();

      await prefs.clearAuthSession();

      expect(await store.currentToken(), token);
      expect(prefs.deviceTrustInstallId, isNotNull);
    });

    test('replaces the token when the install marker is gone', () async {
      final store = TrustedDeviceStore(prefs, secure: secure);
      final original = await store.currentToken();

      await prefs.remove(AppConstants.keyDeviceTrustInstall);

      final rotated = await store.currentToken();
      expect(rotated, isNot(original));
      expect(isDeviceTrustToken(rotated), isTrue);
      expect(secure.values.containsValue(original), isFalse);
    });

    test(
      'forget rotates only after the caller revokes the stored secret',
      () async {
        final store = TrustedDeviceStore(prefs, secure: secure);
        final original = await store.currentToken();

        expect(await store.storedToken(), original);
        final rotated = await store.rotate();

        expect(rotated, isNot(original));
        expect(await store.storedToken(), rotated);
      },
    );
  });

  group('holdAuthScreenForTrustedDeviceCheck', () {
    test('holds login and signup while the server check is in flight', () {
      expect(
        holdAuthScreenForTrustedDeviceCheck(
          resolvingTrustedDevice: true,
          location: RouteNames.login,
        ),
        isTrue,
      );
      expect(
        holdAuthScreenForTrustedDeviceCheck(
          resolvingTrustedDevice: true,
          location: RouteNames.signup,
        ),
        isTrue,
      );
    });

    test('does not hold once the check has finished', () {
      expect(
        holdAuthScreenForTrustedDeviceCheck(
          resolvingTrustedDevice: false,
          location: RouteNames.login,
        ),
        isFalse,
      );
    });

    test('does not hold other routes', () {
      expect(
        holdAuthScreenForTrustedDeviceCheck(
          resolvingTrustedDevice: true,
          location: RouteNames.buyerHome,
        ),
        isFalse,
      );
    });
  });
}
