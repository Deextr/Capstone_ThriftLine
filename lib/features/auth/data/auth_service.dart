import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthUser;

import '../../../core/services/supabase_service.dart';
import '../domain/auth_user.dart';
import 'auth_result.dart';

/// Handles all authentication operations against Supabase.
///
/// Supports:
/// - Email/password sign-up and sign-in
/// - Google Sign-In (native → Supabase ID token)
/// - Sign-out
/// - App-user record fetching and updating
class AuthService {
  AuthService(this._supabaseService);

  final SupabaseService _supabaseService;

  GoTrueClient get _auth => _supabaseService.auth;

  // ─────────────────────────────────────────────────────────────────────────
  // Email / Password
  // ─────────────────────────────────────────────────────────────────────────

  /// Creates a new account with email and password.
  ///
  /// On success, the app-user row in `public.users` is created or refreshed
  /// using the authenticated Supabase user ID.
  Future<AuthResult> signUpWithEmail({
    required String email,
    required String password,
    required String name,
  }) async {
    try {
      debugPrint('AuthService.signUpWithEmail: starting sign-up for $email');
      final response = await _auth.signUp(
        email: email,
        password: password,
        data: {'full_name': name},
      );

      final supabaseUser = response.user;
      if (supabaseUser == null) {
        debugPrint(
          'AuthService.signUpWithEmail: sign-up returned no user for $email. '
          'Session present: ${response.session != null}',
        );
        return AuthResult.failure(
          'Sign-up succeeded but no user was returned. '
          'Please check your email for a confirmation link.',
        );
      }

      if (response.session != null) {
        await _syncExistingUserRecord(
          userId: supabaseUser.id,
          fullName: name,
          avatarUrl: _extractAvatarUrlFromUser(supabaseUser),
        );
      }

      final userRecord = await getUserRecord(supabaseUser.id);
      final authUser = AuthUser.fromSupabase(supabaseUser, userRecord);

      return AuthResult.success(
        authUser,
        requiresEmailVerification: response.session == null,
      );
    } on AuthException catch (e) {
      debugPrint(
        'AuthService.signUpWithEmail AuthException for $email: '
        '${e.message}',
      );
      return AuthResult.failure(_friendlyAuthError(e));
    } catch (e, stackTrace) {
      debugPrint(
        'AuthService.signUpWithEmail unexpected error for $email: $e\n$stackTrace',
      );
      return AuthResult.failure('Something went wrong. Please try again.');
    }
  }

  /// Signs in with email and password.
  Future<AuthResult> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _auth.signInWithPassword(
        email: email,
        password: password,
      );

      final supabaseUser = response.user;
      if (supabaseUser == null) {
        return AuthResult.failure('Sign-in failed. Please try again.');
      }

      await _syncExistingUserRecord(
        userId: supabaseUser.id,
        fullName:
            supabaseUser.userMetadata?['full_name'] as String? ??
            supabaseUser.userMetadata?['name'] as String? ??
            email.split('@').first,
        avatarUrl: _extractAvatarUrlFromUser(supabaseUser),
      );

      final userRecord = await getUserRecord(supabaseUser.id);
      final authUser = AuthUser.fromSupabase(supabaseUser, userRecord);

      return AuthResult.success(authUser);
    } on AuthException catch (e) {
      return AuthResult.failure(_friendlyAuthError(e));
    } catch (e) {
      debugPrint('AuthService.signInWithEmail error: $e');
      return AuthResult.failure('Something went wrong. Please try again.');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Google Sign-In
  // ─────────────────────────────────────────────────────────────────────────

  /// Signs in with Google using the native Google Sign-In flow.
  ///
  /// The flow:
  /// 1. User picks their Google account via the native sheet.
  /// 2. We get a Google ID token.
  /// 3. We pass it to Supabase via `signInWithIdToken()`.
  /// 4. Supabase validates it and creates/returns the session.
  Future<AuthResult> signInWithGoogle() async {
    try {
      final webClientId = dotenv.env['GOOGLE_WEB_CLIENT_ID'] ?? '';

      final googleSignIn = GoogleSignIn(serverClientId: webClientId);

      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        // User cancelled the sign-in flow.
        return AuthResult.failure('Google sign-in was cancelled.');
      }

      final googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;
      final accessToken = googleAuth.accessToken;

      if (idToken == null) {
        return AuthResult.failure(
          'Failed to get Google ID token. Please try again.',
        );
      }

      final response = await _auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );

      final supabaseUser = response.user;
      if (supabaseUser == null) {
        return AuthResult.failure('Google sign-in failed. Please try again.');
      }

      // Ensure the app-user row has the Google user's name and avatar.
      final meta = supabaseUser.userMetadata ?? {};
      final extractedAvatar = _extractAvatarUrlFromUser(supabaseUser) ?? googleUser.photoUrl;
      await _syncExistingUserRecord(
        userId: supabaseUser.id,
        fullName:
            meta['full_name'] as String? ??
            meta['name'] as String? ??
            googleUser.displayName ??
            googleUser.email.split('@').first,
        avatarUrl: extractedAvatar,
      );

      final userRecord = await getUserRecord(supabaseUser.id);
      final authUser = AuthUser.fromSupabase(supabaseUser, userRecord);

      return AuthResult.success(authUser);
    } on AuthException catch (e) {
      return AuthResult.failure(_friendlyAuthError(e));
    } catch (e) {
      debugPrint('AuthService.signInWithGoogle error: $e');
      return AuthResult.failure('Something went wrong. Please try again.');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Sign Out
  // ─────────────────────────────────────────────────────────────────────────

  /// Signs the user out of Supabase and Google.
  Future<void> signOut() async {
    try {
      await GoogleSignIn().signOut();
    } catch (_) {
      // Ignore Google sign-out errors (user may not have signed in via Google).
    }
    await _auth.signOut();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Profile Operations
  // ─────────────────────────────────────────────────────────────────────────

  /// Fetches the `users` row for the given user ID.
  ///
  /// Returns `null` if no app-user row exists yet.
  Future<Map<String, dynamic>?> getUserRecord(String userId) async {
    try {
      final data = await _supabaseService.client
          .from('users')
          .select()
          .eq('user_id', userId)
          .maybeSingle();
      return data;
    } catch (e) {
      debugPrint('AuthService.getUserRecord error: $e');
      return null;
    }
  }

  /// Updates the `users` row for the given user ID.
  Future<void> updateUserRecord(
    String userId,
    Map<String, dynamic> data,
  ) async {
    await _supabaseService.client
        .from('users')
        .update(data)
        .eq('user_id', userId);
  }

  /// Builds an [AuthUser] from the current Supabase session.
  ///
  /// Returns `null` if there is no active session.
  Future<AuthUser?> getCurrentUser() async {
    final supabaseUser = _supabaseService.currentUser;
    if (supabaseUser == null) return null;

    final meta = supabaseUser.userMetadata ?? {};
    await _syncExistingUserRecord(
      userId: supabaseUser.id,
      fullName:
          meta['full_name'] as String? ??
          meta['name'] as String? ??
          supabaseUser.email?.split('@').first ??
          '',
      avatarUrl: _extractAvatarUrlFromUser(supabaseUser),
    );

    final userRecord = await getUserRecord(supabaseUser.id);
    return AuthUser.fromSupabase(supabaseUser, userRecord);
  }

  /// Stream of auth state changes for reactive updates.
  Stream<AuthState> get onAuthStateChange => _supabaseService.onAuthStateChange;

  /// The current session (or null).
  Session? get currentSession => _supabaseService.currentSession;

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────

  String? _extractAvatarUrlFromUser(User? user) {
    if (user == null) return null;
    final meta = user.userMetadata ?? {};
    final url = meta['avatar_url'] as String? ??
        meta['picture'] as String? ??
        meta['avatar'] as String?;
    return (url != null && url.trim().isNotEmpty) ? url.trim() : null;
  }

  /// Ensures an app-user row exists without overwriting user-edited fields.
  ///
  /// If the row already exists (user has logged in before), only `email` and
  /// `avatar` are refreshed — `full_name` and `username` are preserved so
  /// profile edits are never lost on subsequent logins or hot-reloads.
  Future<void> _syncExistingUserRecord({
    required String userId,
    required String fullName,
    String? avatarUrl,
  }) async {
    try {
      // Check if the user row already exists.
      final existing = await _supabaseService.client
          .from('users')
          .select('user_id, full_name')
          .eq('user_id', userId)
          .maybeSingle();

      if (existing != null) {
        // Row exists — only sync email & avatar, never overwrite full_name.
        final updatePayload = <String, dynamic>{
          'updated_at': DateTime.now().toIso8601String(),
        };
        if (avatarUrl != null && avatarUrl.trim().isNotEmpty) {
          // Only update avatar if the user doesn't already have one set,
          // or if you always want the latest Google/provider avatar:
          updatePayload['avatar'] = avatarUrl;
        }
        await _supabaseService.client
            .from('users')
            .update(updatePayload)
            .eq('user_id', userId);
      } else {
        // First time — insert with all fields including full_name.
        final payload = <String, dynamic>{
          'user_id': userId,
          'full_name': fullName,
          'role': 'buyer',
          'trust_score': 80,
          'rating_count': 0,
          'account_status': 'active',
          'updated_at': DateTime.now().toIso8601String(),
        };
        if (avatarUrl != null && avatarUrl.trim().isNotEmpty) {
          payload['avatar'] = avatarUrl;
        }
        await _supabaseService.client.from('users').insert(payload);
      }
    } catch (e) {
      debugPrint('AuthService._syncExistingUserRecord error: $e');
    }
  }

  /// Converts Supabase [AuthException] messages into user-friendly text.
  String _friendlyAuthError(AuthException e) {
    final msg = e.message.toLowerCase();

    if (msg.contains('invalid login credentials') ||
        msg.contains('invalid_credentials')) {
      return 'Invalid email or password. Please try again.';
    }
    if (msg.contains('email not confirmed')) {
      return 'Please verify your email before signing in.';
    }
    if (msg.contains('user already registered') ||
        msg.contains('already been registered')) {
      return 'This email is already registered. Please log in instead.';
    }
    if (msg.contains('rate limit') || msg.contains('too many requests')) {
      return 'Too many attempts. Please wait a moment and try again.';
    }
    if (msg.contains('weak password') || msg.contains('password')) {
      return 'Password must be at least 6 characters.';
    }

    return 'Something went wrong. Please try again.';
  }
}
