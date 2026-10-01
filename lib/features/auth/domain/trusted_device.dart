import 'dart:convert';

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

/// Whether this session used email/password (so the 7-day OTP grant applies).
///
/// Do not use `app_metadata.provider == email` as the first signal. GoTrue
/// often leaves that field as `email` on Google users (companion email
/// identity). Buyer/Seller mode is unrelated.
///
/// Order:
/// 1. JWT `amr` — `oauth` is Google Sign-In; `password` is email/password.
/// 2. Identities — any OAuth provider (e.g. `google`) means this is not the
///    email OTP trusted-device flow unless AMR says `password`.
/// 3. `app_metadata.provider` only when there is no OAuth identity.
bool authSessionUsesEmailPassword({
  required String? lastAuthProvider,
  required Iterable<String> identityProviders,
  Iterable<String> amrMethods = const [],
}) {
  final amr = amrMethods
      .map((m) => m.trim().toLowerCase())
      .where((m) => m.isNotEmpty)
      .toSet();
  if (amr.contains('oauth')) return false;
  if (amr.contains('password')) return true;

  final providers = identityProviders
      .map((p) => p.trim().toLowerCase())
      .where((p) => p.isNotEmpty)
      .toSet();
  final hasOauth = providers.any((p) => p != 'email' && p != 'phone');
  if (hasOauth) return false;
  if (providers.contains('email')) return true;

  final last = lastAuthProvider?.trim().toLowerCase() ?? '';
  return last == 'email';
}

/// `amr[].method` values from a GoTrue access token. Empty when unknown.
List<String> sessionAmrMethodsFromAccessToken(String? accessToken) {
  if (accessToken == null || accessToken.isEmpty) return const [];
  try {
    final parts = accessToken.split('.');
    if (parts.length < 2) return const [];
    var payload = parts[1].replaceAll('-', '+').replaceAll('_', '/');
    final pad = payload.length % 4;
    if (pad != 0) payload += '=' * (4 - pad);
    final map = jsonDecode(utf8.decode(base64.decode(payload)));
    if (map is! Map) return const [];
    final amr = map['amr'];
    if (amr is! List) return const [];
    final methods = <String>[];
    for (final entry in amr) {
      if (entry is Map && entry['method'] is String) {
        methods.add(entry['method'] as String);
      } else if (entry is String) {
        methods.add(entry);
      }
    }
    return methods;
  } catch (_) {
    return const [];
  }
}

/// Last sign-in provider from GoTrue `app_metadata`. Not the email domain.
String? lastAuthProviderFromAppMetadata(Map<String, dynamic>? appMetadata) {
  if (appMetadata == null || appMetadata.isEmpty) return null;
  final provider = appMetadata['provider'];
  if (provider is String && provider.trim().isNotEmpty) return provider.trim();
  final providers = appMetadata['providers'];
  if (providers is List && providers.length == 1) {
    final only = providers.first;
    if (only is String && only.trim().isNotEmpty) return only.trim();
  }
  return null;
}

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
