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

  /// Simple health check — queries the `users` table to verify connectivity.
  ///
  /// Returns `true` if the connection is alive, `false` otherwise.
  Future<bool> healthCheck() async {
    try {
      await client.from('users').select('user_id').limit(1);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Fetches the `users` row for a given [userId].
  Future<Map<String, dynamic>?> fetchUserProfile(String userId) async {
    final response = await client
        .from('users')
        .select()
        .eq('user_id', userId)
        .maybeSingle();
    return response;
  }

  /// Checks if [username] is available (i.e. not used by any user other than [currentUserId]).
  Future<bool> checkUsernameAvailability(
    String username,
    String currentUserId,
  ) async {
    final response = await client
        .from('users')
        .select('user_id')
        .eq('username', username)
        .neq('user_id', currentUserId);

    return (response as List).isEmpty;
  }

  /// Updates profile fields in the `users` table for [userId].
  Future<void> updateUserProfile({
    required String userId,
    required Map<String, dynamic> data,
  }) async {
    await client.from('users').update(data).eq('user_id', userId);
  }
}

