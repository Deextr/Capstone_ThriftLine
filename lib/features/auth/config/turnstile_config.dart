import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Public Turnstile values safe to ship in the Flutter client.
abstract final class TurnstileConfig {
  static String get siteKey => dotenv.env['TURNSTILE_SITE_KEY']?.trim() ?? '';

  /// Used by the mobile WebView integration. On Flutter Web the widget runs on
  /// [pageOrigin]; Cloudflare must allow that hostname in the widget settings.
  static String get baseUrl {
    final configured = dotenv.env['TURNSTILE_BASE_URL']?.trim();
    if (configured != null && configured.isNotEmpty) {
      return _ensureTrailingSlash(configured);
    }
    if (kIsWeb) {
      return _ensureTrailingSlash(pageOrigin);
    }
    final supabaseUrl = dotenv.env['SUPABASE_URL']?.trim() ?? '';
    if (supabaseUrl.startsWith('https://')) {
      return _ensureTrailingSlash(supabaseUrl);
    }
    return 'http://localhost/';
  }

  /// Current browser origin (e.g. `http://localhost:54321`) when running on web.
  static String get pageOrigin {
    if (!kIsWeb) return '';
    final origin = Uri.base.origin;
    if (origin.isEmpty || origin == 'null') return 'http://localhost/';
    return origin;
  }

  static String get pageHostname {
    if (!kIsWeb) return 'localhost';
    final host = Uri.base.host;
    return host.isEmpty ? 'localhost' : host;
  }

  static bool get isConfigured => siteKey.isNotEmpty;

  static String _ensureTrailingSlash(String value) {
    return value.endsWith('/') ? value : '$value/';
  }
}
