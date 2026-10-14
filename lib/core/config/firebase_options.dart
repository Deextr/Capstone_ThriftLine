import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'firebase_config.dart';

/// Firebase options for ThriftLine (Android-focused push).
///
/// Values come from `.env` (`FIREBASE_*`). After creating a Firebase project,
/// copy keys from Project settings → Your apps → Android (`com.example.thriftline`).
///
/// Optional: you may also place `android/app/google-services.json` from Firebase
/// and enable the Google Services Gradle plugin (applied automatically when the
/// file exists).
abstract final class DefaultFirebaseOptions {
  static FirebaseOptions? get currentPlatform {
    if (kIsWeb) return null;
    return FirebaseConfig.options;
  }
}
