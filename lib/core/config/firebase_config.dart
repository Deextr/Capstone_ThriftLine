import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Optional Firebase / FCM configuration from `.env` (no secrets in repo).
abstract final class FirebaseConfig {
  static FirebaseOptions? get options {
    final apiKey = dotenv.env['FIREBASE_API_KEY']?.trim();
    final appId = dotenv.env['FIREBASE_APP_ID']?.trim();
    final messagingSenderId = dotenv.env['FIREBASE_MESSAGING_SENDER_ID']?.trim();
    final projectId = dotenv.env['FIREBASE_PROJECT_ID']?.trim();
    if (apiKey == null ||
        appId == null ||
        messagingSenderId == null ||
        projectId == null) {
      return null;
    }
    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: messagingSenderId,
      projectId: projectId,
      // Required for FCM on Android when not using google-services.json.
      storageBucket: dotenv.env['FIREBASE_STORAGE_BUCKET']?.trim(),
    );
  }

  static bool get isConfigured => options != null;
}
