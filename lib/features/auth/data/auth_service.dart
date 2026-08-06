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
/// - Profile fetching and updating
class AuthService {
  AuthService(this._supabaseService);

  final SupabaseService _supabaseService;

  GoTrueClient get _auth => _supabaseService.auth;

  // ─────────────────────────────────────────────────────────────────────────
  // Email / Password
  // ─────────────────────────────────────────────────────────────────────────

  /// Creates a new account with email and password.
  ///
  /// On success, the Supabase trigger auto-creates a `profiles` row.
  /// We then update the profile with the user's display name.
  Future<AuthResult> signUpWithEmail({
    required String email,
    required String password,
    required String name,
  }) async {
    try {
      final response = await _auth.signUp(
        email: email,
        password: password,
        data: {'full_name': name},
      );

      final supabaseUser = response.user;
      if (supabaseUser == null) {
        return AuthResult.failure(
          'Sign-up succeeded but no user was returned. '
          'Please check your email for a confirmation link.',
        );
      }

      // Update the auto-created profile with the display name.
      await _updateProfileSafe(supabaseUser.id, {'name': name});

      final profile = await getProfile(supabaseUser.id);
      final authUser = AuthUser.fromSupabase(supabaseUser, profile);

      return AuthResult.success(authUser);
    } on AuthException catch (e) {
      return AuthResult.failure(_friendlyAuthError(e));
    } catch (e) {
      debugPrint('AuthService.signUpWithEmail error: $e');
      return AuthResult.failure('An unexpected error occurred. Please try again.');
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

      final profile = await getProfile(supabaseUser.id);
      final authUser = AuthUser.fromSupabase(supabaseUser, profile);

      return AuthResult.success(authUser);
    } on AuthException catch (e) {
      return AuthResult.failure(_friendlyAuthError(e));
    } catch (e) {
      debugPrint('AuthService.signInWithEmail error: $e');
      return AuthResult.failure('An unexpected error occurred. Please try again.');
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

      final googleSignIn = GoogleSignIn(
        serverClientId: webClientId,
      );

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

      // Ensure the profile has the Google user's name and avatar.
      final meta = supabaseUser.userMetadata ?? {};
      await _updateProfileSafe(supabaseUser.id, {
        'name': meta['full_name'] ?? meta['name'] ?? googleUser.displayName ?? '',
        'avatar_url': meta['avatar_url'] ?? googleUser.photoUrl ?? '',
      });

      final profile = await getProfile(supabaseUser.id);
      final authUser = AuthUser.fromSupabase(supabaseUser, profile);

      return AuthResult.success(authUser);
    } on AuthException catch (e) {
      return AuthResult.failure(_friendlyAuthError(e));
    } catch (e) {
      debugPrint('AuthService.signInWithGoogle error: $e');
      return AuthResult.failure(
        'Google sign-in failed. Please try again.',
      );
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

  /// Fetches the `profiles` row for the given user ID.
  ///
  /// Returns `null` if no profile exists yet.
  Future<Map<String, dynamic>?> getProfile(String userId) async {
    try {
      final data = await _supabaseService
          .client
          .from('profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();
      return data;
    } catch (e) {
      debugPrint('AuthService.getProfile error: $e');
      return null;
    }
  }

  /// Updates the `profiles` row for the given user ID.
  Future<void> updateProfile(String userId, Map<String, dynamic> data) async {
    await _supabaseService.client
        .from('profiles')
        .update(data)
        .eq('id', userId);
  }

  /// Builds an [AuthUser] from the current Supabase session.
  ///
  /// Returns `null` if there is no active session.
  Future<AuthUser?> getCurrentUser() async {
    final supabaseUser = _supabaseService.currentUser;
    if (supabaseUser == null) return null;

    final profile = await getProfile(supabaseUser.id);
    return AuthUser.fromSupabase(supabaseUser, profile);
  }

  /// Stream of auth state changes for reactive updates.
  Stream<AuthState> get onAuthStateChange =>
      _supabaseService.onAuthStateChange;

  /// The current session (or null).
  Session? get currentSession => _supabaseService.currentSession;

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────

  /// Updates a profile row, silently ignoring errors.
  ///
  /// Used during sign-up/sign-in where the trigger may not have fired yet
  /// or RLS may block the update for a brief moment.
  Future<void> _updateProfileSafe(String userId, Map<String, dynamic> data) async {
    try {
      await updateProfile(userId, data);
    } catch (e) {
      debugPrint('AuthService._updateProfileSafe (non-fatal): $e');
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
      return 'An account with this email already exists. Try signing in instead.';
    }
    if (msg.contains('rate limit') || msg.contains('too many requests')) {
      return 'Too many attempts. Please wait a moment and try again.';
    }
    if (msg.contains('weak password') || msg.contains('password')) {
      return 'Password must be at least 6 characters.';
    }

    return e.message;
  }
}
