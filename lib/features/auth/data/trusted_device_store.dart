import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/services/shared_preferences_service.dart';
import '../domain/trusted_device.dart';

/// Reads and writes small secrets. Production uses the platform keystore.
abstract class SecureKeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class FlutterSecureKeyValueStore implements SecureKeyValueStore {
  FlutterSecureKeyValueStore()
    : _storage = const FlutterSecureStorage(
        aOptions: AndroidOptions(
          encryptedSharedPreferences: true,
          resetOnError: true,
        ),
        iOptions: IOSOptions(
          accessibility: KeychainAccessibility.first_unlock_this_device,
        ),
      );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

@visibleForTesting
class MemorySecureKeyValueStore implements SecureKeyValueStore {
  final Map<String, String> values = {};

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

/// Install-scoped trusted-device secret.
///
/// The token is created with a CSPRNG and kept in secure storage. A separate
/// non-secret install marker is stored both there and in SharedPreferences.
/// Logout does not clear either. A reinstall wipes SharedPreferences while
/// iOS Keychain can survive, so a missing marker forces a new token and a
/// new OTP instead of reusing a leftover secret.
class TrustedDeviceStore {
  TrustedDeviceStore(this._prefs, {SecureKeyValueStore? secure})
    : _secure = secure;

  static const _tokenKey = 'thriftline_device_trust_token';
  static const _installKey = 'thriftline_device_trust_install';

  final SharedPreferencesService _prefs;
  SecureKeyValueStore? _secure;

  SecureKeyValueStore get _storage => _secure ??= FlutterSecureKeyValueStore();

  /// Token to present after password login. Rotates when this install is not
  /// the one that created the stored secret.
  Future<String> currentToken() async {
    final token = await _storage.read(_tokenKey);
    final secureInstall = await _storage.read(_installKey);
    final prefsInstall = _prefs.deviceTrustInstallId;
    if (_isBound(token, secureInstall, prefsInstall)) return token!;
    return rotate();
  }

  /// Existing secret, even if the install marker no longer matches.
  ///
  /// Used when forgetting a device so a leftover keychain token can still be
  /// revoked. Does not create or rotate a token.
  Future<String?> storedToken() async {
    final token = await _storage.read(_tokenKey);
    if (token != null && isDeviceTrustToken(token)) return token;
    return null;
  }

  Future<String> rotate() async {
    final token = generateDeviceTrustToken();
    final installId = generateDeviceTrustToken();
    await _storage.write(_tokenKey, token);
    await _storage.write(_installKey, installId);
    await _prefs.setDeviceTrustInstallId(installId);
    return token;
  }

  bool _isBound(String? token, String? secureInstall, String? prefsInstall) {
    return token != null &&
        isDeviceTrustToken(token) &&
        secureInstall != null &&
        isDeviceTrustToken(secureInstall) &&
        secureInstall == prefsInstall &&
        token != secureInstall;
  }
}

@visibleForTesting
String generateDeviceTrustToken([Random? random]) {
  final rng = random ?? Random.secure();
  final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
