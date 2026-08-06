import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Centralized Supabase initialization.
///
/// Call [initialize] once in `main()` after `dotenv.load()`.
/// Access the client anywhere via [client].
abstract final class SupabaseConfig {
  static bool _initialized = false;

  /// Initializes the Supabase SDK using credentials from the `.env` file.
  ///
  /// Must be called after `dotenv.load()` and before `runApp()`.
  static Future<void> initialize() async {
    if (_initialized) return;

    final url = dotenv.env['SUPABASE_URL'];
    final anonKey = dotenv.env['SUPABASE_ANON_KEY'];

    if (url == null || url.isEmpty) {
      throw Exception(
        'SUPABASE_URL is not set in the .env file. '
        'Please add it to .env (see .env.example).',
      );
    }
    if (anonKey == null || anonKey.isEmpty) {
      throw Exception(
        'SUPABASE_ANON_KEY is not set in the .env file. '
        'Please add it to .env (see .env.example).',
      );
    }

    await Supabase.initialize(url: url, publishableKey: anonKey);
    _initialized = true;
  }

  /// The initialized [SupabaseClient].
  ///
  /// Throws if [initialize] has not been called.
  static SupabaseClient get client {
    if (!_initialized) {
      throw StateError(
        'SupabaseConfig.initialize() must be called before accessing the client.',
      );
    }
    return Supabase.instance.client;
  }
}
