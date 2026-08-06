import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

/// Provides convenient, centralized access to Supabase services.
///
/// All Supabase interaction in the app should go through this class
/// so that if the SDK changes, only this file needs updating.
class SupabaseService {
  SupabaseService();

  /// The raw [SupabaseClient].
  SupabaseClient get client => SupabaseConfig.client;

  /// Supabase Auth (GoTrue) — sign in, sign up, sign out, session, etc.
  GoTrueClient get auth => client.auth;

  /// Supabase Database (PostgREST) — query builder for any table.
  SupabaseQueryBuilder Function(String table) get from => client.from;

  /// The currently authenticated user, or `null`.
  User? get currentUser => auth.currentUser;

  /// The current session, or `null`.
  Session? get currentSession => auth.currentSession;

  /// Whether a user is currently signed in.
  bool get isAuthenticated => currentUser != null;

  /// Stream of auth state changes (sign-in, sign-out, token refresh, etc.).
  Stream<AuthState> get onAuthStateChange => auth.onAuthStateChange;

  /// Simple health check — queries the `profiles` table to verify connectivity.
  ///
  /// Returns `true` if the connection is alive, `false` otherwise.
  Future<bool> healthCheck() async {
    try {
      await client.from('profiles').select('id').limit(1);
      return true;
    } catch (_) {
      return false;
    }
  }
}
