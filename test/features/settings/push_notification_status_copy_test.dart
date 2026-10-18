import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/core/services/push_notification_service.dart';
import 'package:thriftline/features/settings/domain/push_notification_status_copy.dart';

PushRegistrationDiagnostics _diag({
  bool firebaseConfigured = true,
  bool firebaseInitialized = true,
  bool osPermissionGranted = true,
  bool appPushEnabled = true,
  bool hasDeviceToken = true,
  String? tokenSuffix = 'abc123',
  String? lastError,
}) {
  return PushRegistrationDiagnostics(
    firebaseConfigured: firebaseConfigured,
    firebaseInitialized: firebaseInitialized,
    osPermissionGranted: osPermissionGranted,
    appPushEnabled: appPushEnabled,
    hasDeviceToken: hasDeviceToken,
    tokenSuffix: tokenSuffix,
    lastError: lastError,
  );
}

void main() {
  test('registered status never mentions token suffix', () {
    final message = pushRegistrationStatusMessage(_diag());
    expect(message.toLowerCase(), isNot(contains('token')));
    expect(message, contains('ready'));
  });

  test('userFacingPushRegisterError hides Firebase and FCM details', () {
    expect(
      userFacingPushRegisterError(
        'Firebase is not configured. Add FIREBASE_* keys to .env',
      ),
      isNot(contains('Firebase')),
    );
    expect(
      userFacingPushRegisterError(
        'FCM did not return a device token. Check google-services.json.',
      ),
      isNot(contains('FCM')),
    );
  });

  test('pushDeliveryStatusTitle reflects ready state', () {
    expect(pushDeliveryStatusTitle(_diag()), 'Ready for push alerts');
    expect(
      pushDeliveryStatusTitle(_diag(appPushEnabled: false)),
      'Push alerts off',
    );
  });
}
