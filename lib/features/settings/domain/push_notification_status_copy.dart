import '../../../core/services/push_notification_service.dart';

/// Buyer/seller-facing copy for push registration state (no tokens or dev setup).
String pushRegistrationStatusMessage(PushRegistrationDiagnostics reg) {
  if (!reg.appPushEnabled) {
    return 'Turn on push notifications above to receive alerts on this device.';
  }
  if (!reg.osPermissionGranted) {
    return 'Allow notifications in your phone settings so ThriftLine can send alerts.';
  }
  if (!reg.firebaseConfigured || !reg.firebaseInitialized) {
    return 'Push alerts are not available on this device right now. You can still use in-app notifications.';
  }
  if (reg.hasDeviceToken) {
    return 'This device is ready to receive push alerts.';
  }
  final error = userFacingPushRegisterError(reg.lastError);
  if (error.isNotEmpty) return error;
  return 'This device is not registered for push alerts yet.';
}

String userFacingPushRegisterError(String? lastError) {
  if (lastError == null || lastError.trim().isEmpty) return '';
  final lower = lastError.toLowerCase();
  if (lower.contains('device settings') ||
      lower.contains('allow notifications')) {
    return lastError;
  }
  if (lower.contains('firebase') ||
      lower.contains('fcm') ||
      lower.contains('.env') ||
      lower.contains('google-services')) {
    return 'We could not connect this device for alerts. Try again in a moment.';
  }
  if (lower.contains('supabase') || lower.contains('save device token')) {
    return 'We could not save your alert settings. Try again.';
  }
  if (lower.contains('session not ready')) {
    return 'Please wait a moment and try again.';
  }
  return 'Something went wrong while setting up alerts. Try again.';
}

/// Short label for the combined delivery status row.
String pushDeliveryStatusTitle(PushRegistrationDiagnostics reg) {
  if (!reg.appPushEnabled) return 'Push alerts off';
  if (!reg.osPermissionGranted) return 'Phone permission needed';
  if (reg.readyForPush) return 'Ready for push alerts';
  return 'Setup needed';
}
