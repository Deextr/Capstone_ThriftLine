import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthUser;

import '../../../core/services/supabase_service.dart';
import '../../../core/utils/validators.dart';
import '../domain/auth_error.dart';
import '../domain/auth_user.dart';
import '../domain/legal_documents.dart';
import '../domain/phone_otp.dart';
import '../domain/signup_identity.dart';
import '../domain/trusted_device.dart';
import 'auth_result.dart';

/// Handles all authentication operations against Supabase.
///
/// Supports:
/// - Email/password sign-up and sign-in
/// - Google Sign-In (native → Supabase ID token)
/// - Sign-out
/// - Recording acceptance of the Terms and Privacy Policy
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
  /// [consent] is written into the Supabase user metadata as part of the
  /// sign-up call so the acceptance is recorded atomically with the account.
  ///
  /// When Supabase has "Confirm email" enabled it returns no session, and the
  /// result carries `requiresEmailVerification` so the caller can tell the
  /// user to open the confirmation link.
  Future<AuthResult> signUpWithEmail({
    required String email,
    required String password,
    required String name,
    required LegalConsent consent,
  }) async {
    final sanitizedName = Validators.normalizeFullName(name);
    final nameError = Validators.name(sanitizedName);
    if (nameError != null) {
      return AuthResult.failure(nameError);
    }

    try {
      final response = await _auth.signUp(
        email: email,
        password: password,
        data: {'full_name': sanitizedName, ...consent.toMetadata()},
      );

      final supabaseUser = response.user;
      if (supabaseUser == null) {
        return AuthResult.failure(
          'We could not complete your sign-up. Please try again.',
        );
      }

      // Confirm-email-on: empty identities + no session means the address is
      // taken. Confirm-email-off (ThriftLine): GoTrue may instead return a
      // session that already has a Google identity — that is the same account,
      // not a new registration. Never treat that as a successful signup.
      final providers =
          supabaseUser.identities?.map((i) => i.provider) ?? const <String>[];
      final outcome = classifySignupIdentities(
        hasSession: response.session != null,
        providers: providers,
      );
      if (outcome != SignupOutcome.proceed) {
        if (response.session != null) {
          try {
            await _auth.signOut();
          } catch (e) {
            debugPrint('AuthService.signUpWithEmail signOut after reject: $e');
          }
        }
        return AuthResult.failure(existingAccountSignupMessage(outcome));
      }

      if (response.session == null) {
        return AuthResult.success(null, requiresEmailVerification: true);
      }

      await _refreshProviderAvatar(
        userId: supabaseUser.id,
        avatarUrl: _extractAvatarUrlFromUser(supabaseUser),
      );

      final userRecord = await getUserRecord(supabaseUser.id);
      return AuthResult.success(
        await hydrateUser(supabaseUser, userRecord),
        requiresEmailOtp: true,
      );
    } on AuthException catch (e) {
      debugPrint('AuthService.signUpWithEmail failed: ${_describe(e)}');
      return AuthResult.failure(_friendlySignupAuthError(e));
    } catch (e) {
      debugPrint('AuthService.signUpWithEmail unexpected error: $e');
      if (e.toString().toLowerCase().contains('already exists')) {
        return AuthResult.failure(
          existingAccountSignupMessage(SignupOutcome.alreadyRegistered),
        );
      }
      return AuthResult.failure('Something went wrong. Please try again.');
    }
  }

  /// Signs in with email and password.
  ///
  /// Password success still returns `requiresEmailOtp`. The caller may clear
  /// that gate only after [isTrustedDevice] returns true for this user.
  Future<AuthResult> signInWithEmail({
    required String email,
    required String password,
    required LegalConsent consent,
    required String turnstileToken,
  }) async {
    try {
      final response = await _supabaseService.client.functions.invoke(
        'sign-in-with-email',
        body: {
          'email': email.trim(),
          'password': password,
          'turnstile_token': turnstileToken.trim(),
        },
      );

      final data = response.data;
      if (data is Map) {
        final code = data['code']?.toString();
        final serverError = data['error']?.toString();
        if (serverError != null && serverError.isNotEmpty) {
          return AuthResult.failure(
            emailLoginUiMessage(code: code, serverError: serverError),
          );
        }
        if (response.status >= 400) {
          return AuthResult.failure(emailLoginUiMessage(code: code));
        }

        final session = data['session'];
        if (session is! Map) {
          return AuthResult.failure('Sign-in failed. Please try again.');
        }
        final accessToken = session['access_token']?.toString() ?? '';
        final refreshToken = session['refresh_token']?.toString() ?? '';
        if (accessToken.isEmpty || refreshToken.isEmpty) {
          return AuthResult.failure('Sign-in failed. Please try again.');
        }

        final authResponse = await _auth.setSession(
          refreshToken,
          accessToken: accessToken,
        );

        final supabaseUser = authResponse.user;
        if (supabaseUser == null) {
          return AuthResult.failure('Sign-in failed. Please try again.');
        }

        await recordConsent(consent);

        await _refreshProviderAvatar(
          userId: supabaseUser.id,
          avatarUrl: _extractAvatarUrlFromUser(supabaseUser),
        );

        final userRecord = await getUserRecord(supabaseUser.id);
        return AuthResult.success(
          await hydrateUser(supabaseUser, userRecord),
          requiresEmailOtp: true,
        );
      }

      if (response.status >= 400) {
        debugPrint(
          'AuthService.signInWithEmail failed: status=${response.status}',
        );
        return AuthResult.failure(emailLoginUiMessage());
      }
      return AuthResult.failure('Sign-in failed. Please try again.');
    } on FunctionException catch (e) {
      debugPrint('AuthService.signInWithEmail failed: status=${e.status}');
      return AuthResult.failure(
        emailLoginUiMessage(
          code: _functionExceptionCode(e),
          serverError: _functionExceptionMessage(e),
        ),
      );
    } on AuthException catch (e) {
      debugPrint('AuthService.signInWithEmail failed: ${_describe(e)}');
      return AuthResult.failure(_friendlyAuthError(e));
    } catch (e) {
      debugPrint('AuthService.signInWithEmail error: $e');
      return AuthResult.failure('Something went wrong. Please try again.');
    }
  }

  /// Asks the `send-password-reset` Edge Function to email a recovery link.
  ///
  /// GoTrue's own mailer is not used. The function returns the same success
  /// response when the address is missing or belongs only to Google, so the
  /// UI cannot tell those cases apart. Delivery and rate-limit failures are
  /// the only errors shown.
  Future<String?> requestPasswordReset({
    required String email,
    required String turnstileToken,
  }) async {
    try {
      final response = await _supabaseService.client.functions.invoke(
        'send-password-reset',
        body: {
          'email': email.trim(),
          'turnstile_token': turnstileToken.trim(),
        },
      );
      final data = response.data;
      if (data is Map && data['error'] != null) {
        return passwordResetUiMessage(data['error'].toString());
      }
      if (response.status >= 400) {
        debugPrint(
          'AuthService.requestPasswordReset failed: status=${response.status}',
        );
        return passwordResetUiMessage(null);
      }
      return null;
    } on FunctionException catch (e) {
      debugPrint('AuthService.requestPasswordReset failed: status=${e.status}');
      return passwordResetUiMessage(_functionExceptionMessage(e));
    } catch (e) {
      debugPrint('AuthService.requestPasswordReset failed');
      return passwordResetUiMessage(null);
    }
  }

  /// Sets a new password during an active Supabase recovery session.
  Future<String?> updatePasswordForRecovery({required String password}) async {
    if (_auth.currentSession == null) {
      return 'Your reset session expired. Request a new password reset email.';
    }
    try {
      await _auth.updateUser(UserAttributes(password: password));
      return null;
    } on AuthException catch (e) {
      debugPrint(
        'AuthService.updatePasswordForRecovery failed: ${_describe(e)}',
      );
      final parsed = parseGoTrueError(code: e.code, message: e.message);
      if (parsed.code == 'weak_password') {
        return 'Password must be at least 6 characters.';
      }
      final msg = parsed.message.toLowerCase();
      if (msg.contains('session') && msg.contains('missing')) {
        return 'Your reset session expired. Request a new password reset email.';
      }
      if (msg.contains('same password') || msg.contains('different')) {
        return 'Choose a new password that is different from your old one.';
      }
      if (msg.contains('weak password') || msg.contains('password')) {
        return 'Password must be at least 6 characters.';
      }
      return 'Could not update your password. '
          'Request a new reset link and try again.';
    } catch (e) {
      debugPrint('AuthService.updatePasswordForRecovery error: $e');
      return 'Could not update your password. Please try again.';
    }
  }

  /// Stamps the accepted legal document version onto the signed-in account.
  ///
  /// Requires an active session; failures are non-fatal and never block a
  /// sign-in that Supabase already approved.
  Future<void> recordConsent(LegalConsent consent) async {
    try {
      await _auth.updateUser(UserAttributes(data: consent.toMetadata()));
    } catch (e) {
      debugPrint('AuthService.recordConsent error: $e');
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
  Future<AuthResult> signInWithGoogle({required LegalConsent consent}) async {
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

      await recordConsent(consent);

      // The profile row and its full_name come from the database trigger; only
      // the avatar can change between Google logins.
      await _refreshProviderAvatar(
        userId: supabaseUser.id,
        avatarUrl:
            _extractAvatarUrlFromUser(supabaseUser) ?? googleUser.photoUrl,
      );

      final userRecord = await getUserRecord(supabaseUser.id);
      final authUser = await hydrateUser(supabaseUser, userRecord);

      return AuthResult.success(authUser);
    } on AuthException catch (e) {
      debugPrint('AuthService.signInWithGoogle failed: ${_describe(e)}');
      return AuthResult.failure(_friendlyGoogleAuthError(e));
    } catch (e, stackTrace) {
      debugPrint('AuthService.signInWithGoogle failed');
      debugPrintStack(stackTrace: stackTrace);
      return AuthResult.failure('Google sign-in failed. Please try again.');
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
    final sessionUser = _supabaseService.currentUser;
    if (sessionUser == null) return null;

    var supabaseUser = sessionUser;
    try {
      final remoteUser = (await _auth.getUser()).user;
      if (remoteUser != null) supabaseUser = remoteUser;
    } catch (e) {
      debugPrint('AuthService.getCurrentUser identity refresh: $e');
    }

    final userRecord = await getUserRecord(supabaseUser.id);
    return hydrateUser(supabaseUser, userRecord);
  }

  /// Builds an [AuthUser] with seller verification and shop profile attached.
  Future<AuthUser> hydrateUser(
    User supabaseUser,
    Map<String, dynamic>? profile,
  ) async {
    Map<String, dynamic>? verification;
    Map<String, dynamic>? sellerProfile;
    try {
      verification = await _supabaseService.client
          .from('user_verifications')
          .select()
          .eq('user_id', supabaseUser.id)
          .order('submitted_at', ascending: false)
          .limit(1)
          .maybeSingle();
    } catch (e) {
      debugPrint('AuthService.hydrateUser verification error: $e');
    }
    try {
      sellerProfile = await _supabaseService.client
          .from('seller_profiles')
          .select()
          .eq('seller_id', supabaseUser.id)
          .maybeSingle();
    } catch (e) {
      debugPrint('AuthService.hydrateUser seller profile error: $e');
    }
    return AuthUser.fromSupabase(
      supabaseUser,
      profile,
      verification: verification,
      sellerProfile: sellerProfile,
      sessionAmrMethods: sessionAmrMethodsFromAccessToken(
        _supabaseService.currentSession?.accessToken,
      ),
    );
  }

  /// Sends a 6-digit email code through the `send-email-otp` Edge Function.
  ///
  /// Gmail SMTP credentials never leave the server. Returns an error message
  /// on failure, or `null` on success.
  Future<String?> sendEmailOtp() async {
    try {
      final response = await _supabaseService.client.functions.invoke(
        'send-email-otp',
        body: const {'purpose': 'login_verify'},
      );
      return _functionError(response);
    } on FunctionException catch (e) {
      debugPrint(
        'AuthService.sendEmailOtp failed: ${e.reasonPhrase} ${e.details}',
      );
      return _functionExceptionMessage(e) ??
          'We could not send the email. Please try again.';
    } catch (e) {
      debugPrint('AuthService.sendEmailOtp error: $e');
      return 'We could not send the email. Please try again.';
    }
  }

  /// Asks the server whether this install token is still trusted for the
  /// signed-in user. Anything other than an explicit true stays untrusted.
  ///
  /// The token is sent only in this request body and is not written to logs.
  Future<bool> isTrustedDevice({required String deviceToken}) async {
    try {
      final response = await _supabaseService.client.functions.invoke(
        'check-trusted-device',
        body: {'device_token': deviceToken},
      );
      final data = response.data;
      if (response.status >= 400) return false;
      return data is Map && data['trusted'] == true && data['error'] == null;
    } on FunctionException catch (e) {
      debugPrint('AuthService.isTrustedDevice failed: status=${e.status}');
      return false;
    } catch (_) {
      debugPrint('AuthService.isTrustedDevice failed');
      return false;
    }
  }

  /// Confirms the email code through the `verify-email-otp` Edge Function.
  ///
  /// [deviceToken] is optional. When it is present the server hashes it and
  /// starts a 7-day trusted-device grant. A missing token still verifies the
  /// code and leaves the device untrusted.
  Future<String?> sendEmailChangeOtp({required String newEmail}) async {
    try {
      final response = await _supabaseService.client.functions.invoke(
        'send-email-otp',
        body: {
          'purpose': 'email_change',
          'new_email': newEmail.trim(),
        },
      );
      return _functionError(response);
    } on FunctionException catch (e) {
      debugPrint(
        'AuthService.sendEmailChangeOtp failed: ${e.reasonPhrase} ${e.details}',
      );
      return _functionExceptionMessage(e) ??
          'We could not send the verification email.';
    } catch (e) {
      debugPrint('AuthService.sendEmailChangeOtp error: $e');
      return 'We could not send the verification email.';
    }
  }

  Future<({String? error, String? email})> confirmEmailChangeOtp({
    required String token,
  }) async {
    try {
      final response = await _supabaseService.client.functions.invoke(
        'verify-email-otp',
        body: {
          'purpose': 'email_change',
          'token': token,
        },
      );
      final err = _functionError(response);
      if (err != null) return (error: err, email: null);
      final data = response.data;
      if (data is Map && data['email'] is String) {
        return (error: null, email: data['email'] as String);
      }
      return (error: null, email: null);
    } on FunctionException catch (e) {
      debugPrint('AuthService.confirmEmailChangeOtp failed: status=${e.status}');
      return (
        error: _functionExceptionMessage(e) ??
            'Could not verify that code. Please try again.',
        email: null,
      );
    } catch (_) {
      return (
        error: 'Could not verify that code. Please try again.',
        email: null,
      );
    }
  }

  Future<String?> verifyEmailOtp({
    required String token,
    String? deviceToken,
    String? platform,
  }) async {
    try {
      final response = await _supabaseService.client.functions.invoke(
        'verify-email-otp',
        body: {
          'purpose': 'login_verify',
          'token': token,
          'device_token': ?deviceToken,
          'platform': ?platform,
        },
      );
      return _functionError(response);
    } on FunctionException catch (e) {
      debugPrint('AuthService.verifyEmailOtp failed: status=${e.status}');
      return _functionExceptionMessage(e) ??
          'Could not verify that code. Please try again.';
    } catch (_) {
      debugPrint('AuthService.verifyEmailOtp failed');
      return 'Could not verify that code. Please try again.';
    }
  }

  /// Revokes this install for the signed-in user. Does not sign the user out.
  Future<String?> revokeTrustedDevice({required String deviceToken}) async {
    try {
      final response = await _supabaseService.client.functions.invoke(
        'revoke-trusted-device',
        body: {'device_token': deviceToken},
      );
      return _functionError(response);
    } on FunctionException catch (e) {
      debugPrint('AuthService.revokeTrustedDevice failed: status=${e.status}');
      return _functionExceptionMessage(e) ??
          'Could not forget this device. Please try again.';
    } catch (_) {
      debugPrint('AuthService.revokeTrustedDevice failed');
      return 'Could not forget this device. Please try again.';
    }
  }

  /// Sends a 6-digit SMS code through the `send-phone-otp` Edge Function.
  ///
  /// The FMCSMS API key never leaves the server.
  Future<PhoneOtpResult> sendPhoneOtp(String phone) async {
    try {
      final response = await _supabaseService.client.functions.invoke(
        'send-phone-otp',
        body: {'phone': phone},
      );
      return _phoneOtpResult(
        response,
        fallback: 'We could not send the verification code. Please try again.',
      );
    } on FunctionException catch (e) {
      debugPrint('AuthService.sendPhoneOtp failed: ${e.reasonPhrase}');
      return _phoneOtpFromException(
        e,
        fallback: 'We could not send the verification code. Please try again.',
      );
    } catch (e) {
      debugPrint('AuthService.sendPhoneOtp error: $e');
      return const PhoneOtpResult.failure(
        'We could not send the verification code. Check your connection and try again.',
      );
    }
  }

  /// Confirms the SMS code through the `verify-phone-otp` Edge Function.
  Future<PhoneOtpResult> verifyPhoneOtp({
    required String phone,
    required String token,
  }) async {
    try {
      final response = await _supabaseService.client.functions.invoke(
        'verify-phone-otp',
        body: {'phone': phone, 'token': token},
      );
      return _phoneOtpResult(
        response,
        fallback: 'Could not verify that code. Please try again.',
      );
    } on FunctionException catch (e) {
      debugPrint('AuthService.verifyPhoneOtp failed: ${e.reasonPhrase}');
      return _phoneOtpFromException(
        e,
        fallback: 'Could not verify that code. Please try again.',
      );
    } catch (e) {
      debugPrint('AuthService.verifyPhoneOtp error: $e');
      return const PhoneOtpResult.failure(
        'Could not verify that code. Check your connection and try again.',
      );
    }
  }

  String? _functionError(FunctionResponse response) {
    final data = response.data;
    if (data is Map && data['error'] != null) {
      return data['error'].toString();
    }
    if (response.status >= 400) {
      return 'Request failed. Please try again.';
    }
    return null;
  }

  String? _functionExceptionMessage(FunctionException e) {
    final details = e.details;
    if (details is Map && details['error'] != null) {
      return details['error'].toString();
    }
    if (details is String && details.trim().isNotEmpty) {
      return details;
    }
    return e.reasonPhrase;
  }

  String? _functionExceptionCode(FunctionException e) {
    final details = e.details;
    if (details is Map && details['code'] != null) {
      return details['code'].toString();
    }
    return null;
  }

  PhoneOtpResult _phoneOtpResult(
    FunctionResponse response, {
    required String fallback,
  }) {
    return _phoneOtpFromData(
      response.data,
      status: response.status,
      fallback: fallback,
    );
  }

  PhoneOtpResult _phoneOtpFromException(
    FunctionException e, {
    required String fallback,
  }) {
    return _phoneOtpFromData(e.details, status: e.status, fallback: fallback);
  }

  PhoneOtpResult _phoneOtpFromData(
    Object? data, {
    required int status,
    required String fallback,
  }) {
    if (data is Map) {
      final error = data['error']?.toString();
      final code = data['code']?.toString();
      final retry = _asInt(data['retry_after_seconds']);
      if (error != null && error.isNotEmpty) {
        return PhoneOtpResult.failure(
          error,
          code: code,
          retryAfterSeconds: retry,
        );
      }
      if (status < 400) {
        return PhoneOtpResult.success(retryAfterSeconds: retry ?? 60);
      }
    }
    if (data is String && data.trim().isNotEmpty && status >= 400) {
      return PhoneOtpResult.failure(data);
    }
    if (status >= 400) return PhoneOtpResult.failure(fallback);
    return PhoneOtpResult.success(retryAfterSeconds: 60);
  }

  int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
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
    final url =
        meta['avatar_url'] as String? ??
        meta['picture'] as String? ??
        meta['avatar'] as String?;
    return (url != null && url.trim().isNotEmpty) ? url.trim() : null;
  }

  /// Refreshes the provider-supplied avatar on the app-user row.
  ///
  /// The row itself is created by the `handle_new_auth_user` database trigger
  /// when Supabase inserts into `auth.users`, so there is nothing for the client
  /// to create — `public.users` has no INSERT policy at all. This only exists
  /// because the trigger runs once at sign-up, whereas a Google avatar can
  /// change between logins.
  ///
  /// `full_name` and `username` are never touched here so profile edits survive
  /// subsequent logins. Failures are non-fatal: a stale avatar must not block a
  /// sign-in that Supabase already approved.
  Future<void> _refreshProviderAvatar({
    required String userId,
    String? avatarUrl,
  }) async {
    final url = avatarUrl?.trim();
    if (url == null || url.isEmpty) return;

    try {
      await _supabaseService.client
          .from('users')
          .update({'avatar': url})
          .eq('user_id', userId);
    } catch (e) {
      debugPrint('AuthService._refreshProviderAvatar error: $e');
    }
  }

  /// Diagnostic summary of a Supabase auth failure.
  ///
  /// Includes the status, code, and server message — none of which contain
  /// credentials or addresses — so failures are traceable without leaking
  /// anything sensitive into the logs.
  String _describe(AuthException e) =>
      'status=${e.statusCode ?? '-'} code=${e.code ?? '-'} "${e.message}"';

  /// Converts Supabase [AuthException]s into user-friendly text.
  ///
  /// Matches on the stable error code first and falls back to message text for
  /// responses that predate codes.
  String _friendlyAuthError(AuthException e) {
    final parsed = parseGoTrueError(code: e.code, message: e.message);
    switch (parsed.code) {
      case 'invalid_credentials':
        return 'Invalid email or password. Please try again.';
      case 'email_not_confirmed':
        return 'Please confirm your email using the link we sent, '
            'then sign in again.';
      case 'user_already_exists':
      case 'email_exists':
      case 'identity_already_exists':
        return 'This email is already registered. Please log in instead.';
      case 'over_email_send_rate_limit':
        return 'Too many emails requested. Please wait a minute and '
            'try again.';
      case 'over_request_rate_limit':
        return 'Too many attempts. Please wait a moment and try again.';
      case 'captcha_failed':
        return 'Human verification failed. Please try again.';
      case 'weak_password':
        return 'Password must be at least 6 characters.';
    }

    final msg = parsed.message.toLowerCase();

    // Supabase reports a failing SMTP configuration as a generic 500, so it
    // has to be recognised by message text. Without this it is
    // indistinguishable from any other backend fault.
    if (msg.contains('error sending') ||
        msg.contains('smtp') ||
        msg.contains('email provider')) {
      return 'We could not send the confirmation email. '
          'Please try again in a moment.';
    }
    if (msg.contains('invalid login credentials') ||
        msg.contains('invalid_credentials')) {
      return 'Invalid email or password. Please try again.';
    }
    if (msg.contains('email not confirmed')) {
      return 'Please confirm your email using the link we sent, '
          'then sign in again.';
    }
    if (msg.contains('user already registered') ||
        msg.contains('already been registered') ||
        msg.contains('already exists')) {
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

  String _friendlySignupAuthError(AuthException e) {
    final parsed = parseGoTrueError(code: e.code, message: e.message);
    if (isOauthAccountSignupBlocked(parsed)) {
      return existingAccountSignupMessage(SignupOutcome.existingGoogleAccount);
    }
    if (isExistingAccountAuthError(parsed)) {
      return existingAccountSignupMessage(SignupOutcome.alreadyRegistered);
    }
    return _friendlyAuthError(e);
  }

  String _friendlyGoogleAuthError(AuthException e) {
    if (_isExistingAccountConflict(e)) {
      return existingEmailPasswordAccountMessage;
    }
    return _friendlyAuthError(e);
  }

  /// GoTrue / trigger failures that mean this email already has an account.
  /// Does not look up public.users — only Auth error codes and messages.
  bool _isExistingAccountConflict(AuthException e) {
    return isExistingAccountAuthError(
      parseGoTrueError(code: e.code, message: e.message),
    );
  }
}
