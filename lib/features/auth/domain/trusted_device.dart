import 'package:flutter/foundation.dart';

/// Email OTP is skipped only after password success and an explicit server
/// grant. A failed, missing, or false check must keep the OTP step.
bool shouldSkipEmailOtp({
  required bool passwordAccepted,
  required bool serverTrusted,
}) => passwordAccepted && serverTrusted;

/// 32-byte token, lowercase hex. This is an install secret, not a hardware id.
bool isDeviceTrustToken(String value) =>
    RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

/// Trusted-device logout copy is only for email/password accounts.
/// Google Sign-In never uses the 7-day email code grant.
bool showEmailTrustedDeviceLogout({required bool usesEmailPasswordAuth}) =>
    usesEmailPasswordAuth;

/// Coarse label stored beside the hash. It is never used to decide trust.
String trustedDevicePlatformLabel(TargetPlatform platform) {
  switch (platform) {
    case TargetPlatform.android:
      return 'android';
    case TargetPlatform.iOS:
      return 'ios';
    default:
      return 'other';
  }
}
