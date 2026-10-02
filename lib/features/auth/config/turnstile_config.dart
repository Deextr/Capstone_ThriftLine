import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Public Turnstile values safe to ship in the Flutter client.
abstract final class TurnstileConfig {
  static String get siteKey => dotenv.env['TURNSTILE_SITE_KEY']?.trim() ?? '';

  /// Must match a hostname on the Cloudflare Turnstile widget allowlist.
  static String get baseUrl {
    final configured = dotenv.env['TURNSTILE_BASE_URL']?.trim();
    if (configured != null && configured.isNotEmpty) return configured;
    final supabaseUrl = dotenv.env['SUPABASE_URL']?.trim() ?? '';
    if (supabaseUrl.startsWith('https://')) return '$supabaseUrl/';
    return 'https://localhost/';
  }

  static bool get isConfigured => siteKey.isNotEmpty;
}
