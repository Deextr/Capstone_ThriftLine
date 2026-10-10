import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthState, AuthChangeEvent;

import '../core/services/shared_preferences_service.dart';
import '../features/auth/data/auth_service.dart';
import '../features/auth/data/auth_result.dart';
import '../features/auth/data/email_login_result.dart';
import '../features/auth/data/trusted_device_store.dart';
import '../features/auth/domain/account_mode.dart';
import '../features/auth/domain/auth_error.dart';
import '../features/auth/domain/auth_user.dart';
import '../features/auth/domain/legal_documents.dart';
import '../features/auth/domain/login_portal.dart';
import '../features/auth/domain/phone_otp.dart';
import '../features/auth/domain/trusted_device.dart';
import '../models/enums.dart';

/// TEMPORARY: skips the email OTP step on login and sign-up.
/// Only takes effect in debug builds. Set to false to restore OTP.
const bool kBypassEmailOtp = true;
bool get _bypassOtp => kDebugMode && kBypassEmailOtp;

/// Router-facing gate: a restored session is not enough while email OTP is
/// still outstanding.
bool authIsFullyAuthenticated({
  required bool hasSession,
  required bool emailOtpPending,
}) => hasSession && !emailOtpPending;

/// Recovery sessions must not write ThriftLine's normal login cache.
@visibleForTesting
bool shouldPersistAuthSession({
  required bool passwordRecoveryActive,
  required bool passwordRecoveryPending,
}) => !passwordRecoveryActive && !passwordRecoveryPending;

@visibleForTesting
bool shouldDiscardRecoverySessionOnStartup({
  required bool passwordRecoveryPending,
}) => passwordRecoveryPending;

/// Manages authentication state, session persistence, and role detection.
///
/// Wraps [AuthService] (Supabase) and caches minimal session data
/// in [SharedPreferencesService] for fast cold-start restoration.
class AuthProvider extends ChangeNotifier {
  AuthProvider(
    this._prefs,
    this._authService, {
    TrustedDeviceStore? trustedDevices,
  }) : _trustedDevices = trustedDevices ?? TrustedDeviceStore(_prefs);

  final SharedPreferencesService _prefs;
  final AuthService _authService;
  final TrustedDeviceStore _trustedDevices;

  AuthUser? _user;
  bool _isLoading = false;
  bool _isInitialized = false;
  bool _emailOtpPending = false;
  bool _resolvingTrustedDevice = false;
  bool _passwordRecoveryActive = false;
  AccountMode _activeAccount = AccountMode.buyer;

  StreamSubscription? _authSubscription;

  AuthUser? get user => _user;
  bool get isLoading => _isLoading;
  bool get isInitialized => _isInitialized;
  bool get isAuthenticated => _user != null;
  bool get isEmailOtpPending => _emailOtpPending;

  /// True after the user opens a valid Supabase password recovery deep link.
  bool get isPasswordRecoveryActive => _passwordRecoveryActive;

  /// Current session used email/password — not Gmail, not Buyer/Seller mode.
  ///
  /// Computed from the live GoTrue session (JWT `amr` + identities) so a
  /// Buyer ↔ Seller switch cannot keep a stale trusted-device flag.
  bool get usesEmailPasswordAuth {
    final session = _authService.currentSession;
    return authSessionUsesEmailPassword(
      lastAuthProvider: lastAuthProviderFromAppMetadata(
        session?.user.appMetadata,
      ),
      identityProviders: <String>{
        ...?_user?.authIdentityProviders,
        ...?session?.user.identities?.map((i) => i.provider),
      },
      amrMethods: sessionAmrMethodsFromAccessToken(session?.accessToken),
    );
  }

  /// True while email/password sign-in is waiting on the trusted-device check.
  /// The router stays on the login screen until this clears.
  bool get isResolvingTrustedDevice => _resolvingTrustedDevice;

  /// Session exists and the email OTP step is not still outstanding.
  bool get isFullyAuthenticated =>
      authIsFullyAuthenticated(
        hasSession: isAuthenticated,
        emailOtpPending: _emailOtpPending,
      ) &&
      !_passwordRecoveryActive;

  /// Current Buyer/Seller workspace. Independent of `users.role`.
  AccountMode get activeAccount => _activeAccount;

  bool get hasSellerAccess => _user?.hasSellerAccess ?? false;

  bool get canSwitchAccounts =>
      authCanSwitchAccounts(hasSellerAccess: hasSellerAccess, isAdmin: isAdmin);

  bool get isBuyer => !isAdmin && _activeAccount == AccountMode.buyer;
  bool get isSeller => !isAdmin && _activeAccount == AccountMode.seller;
  bool get isAdmin => _user?.isAdmin ?? false;
  bool get isSuperAdmin => _user?.isSuperAdmin ?? false;
  bool get canUseAdminPortal => _user?.canUseAdminPortal ?? false;
  bool get isDeactivatedAdministrator =>
      _user?.isDeactivatedAdministrator ?? false;
  UserRole? get role => _user?.role;

  String? get username => _user?.username;
  String? get displayName {
    final user = _user;
    if (user == null) return null;
    if (_activeAccount == AccountMode.seller) {
      return user.shopName ?? user.name;
    }
    return user.name;
  }

  /// Profile photo for the active Buyer/Seller workspace.
  String get activeAvatarUrl => avatarUrlForMode(_activeAccount);

  /// Profile photo for a workspace without changing the active mode.
  String avatarUrlForMode(AccountMode mode) {
    final user = _user;
    if (user == null) return '';
    if (mode == AccountMode.seller && user.sellerAvatarUrl.trim().isNotEmpty) {
      return user.sellerAvatarUrl;
    }
    return user.avatarUrl;
  }

  Future<String?> sendEmailChangeOtp(String newEmail) =>
      _authService.sendEmailChangeOtp(newEmail: newEmail);

  Future<({String? error, String? email})> confirmEmailChangeOtp(
    String token,
  ) async {
    final result = await _authService.confirmEmailChangeOtp(token: token);
    if (result.error == null && result.email != null && _user != null) {
      _user = _user!.copyWith(email: result.email);
      await _saveSession(_user!);
      notifyListeners();
    }
    return result;
  }

  Future<void> updateSellerAvatarUrl(String url) async {
    if (_user == null) return;
    _user = _user!.copyWith(sellerAvatarUrl: url);
    await _saveSession(_user!);
    notifyListeners();
  }

  String get homeRoute =>
      homeRouteFor(isAdmin: isAdmin, activeAccount: _activeAccount);

  /// Moves between Buyer and Seller chrome on the same authenticated user.
  ///
  /// Does not create credentials, change `users.role`, or copy profile rows.
  Future<void> switchActiveAccount(AccountMode mode) async {
    final user = _user;
    if (user == null || !canSwitchAccounts) return;
    if (_activeAccount == mode) return;
    _activeAccount = mode;
    await _prefs.setActiveAccount(userId: user.id, mode: mode.name);
    await reloadUser();
  }

  /// Restores a session from Supabase (auto-login via persisted JWT).
  ///
  /// Called once at app startup from `main()`.
  Future<void> init() async {
    try {
      if (shouldDiscardRecoverySessionOnStartup(
        passwordRecoveryPending: _prefs.isPasswordRecoveryPending,
      )) {
        await _terminatePasswordRecoverySession(clearPendingFlag: true);
      }

      // Supabase SDK automatically restores the session from secure storage.
      final currentUser = await _authService.getCurrentUser();
      if (currentUser != null && currentUser.sessionBlockMessage == null) {
        _user = currentUser;
        // TEMP: debug OTP bypass clears pending for non-admins only.
        final bypassOtpForUser = _bypassOtp && !currentUser.isAdmin;
        _emailOtpPending = bypassOtpForUser ? false : _prefs.isEmailOtpPending;
        if (bypassOtpForUser) await _prefs.setEmailOtpPending(false);
        _syncActiveAccount(currentUser, restoreFromPrefs: true);
        await _saveSession(currentUser);
      } else {
        if (currentUser != null) {
          await _authService.signOut();
        }
        await _clearSession();
      }
    } catch (e) {
      debugPrint('AuthProvider.init error: $e');
      await _clearSession();
    }

    // Listen for future auth state changes (token refresh, sign-out, etc.).
    _authSubscription = _authService.onAuthStateChange.listen(
      _handleAuthStateChange,
    );

    _isInitialized = true;
    notifyListeners();
  }

  /// Handles real-time auth events from Supabase.
  Future<void> _handleAuthStateChange(AuthState event) async {
    final authEvent = event.event;

    if (authEvent == AuthChangeEvent.signedOut) {
      _user = null;
      _emailOtpPending = false;
      _passwordRecoveryActive = false;
      _activeAccount = AccountMode.buyer;
      await _clearSession();
      notifyListeners();
    } else if (authEvent == AuthChangeEvent.passwordRecovery) {
      await _activatePasswordRecovery();
      if (_authService.currentSession == null) return;
      final currentUser = await _authService.getCurrentUser();
      if (currentUser == null || _authService.currentSession == null) return;
      if (currentUser.sessionBlockMessage != null) {
        await _authService.signOut();
        return;
      }
      _user = currentUser;
      notifyListeners();
    } else if (authEvent == AuthChangeEvent.signedIn ||
        authEvent == AuthChangeEvent.tokenRefreshed ||
        authEvent == AuthChangeEvent.userUpdated) {
      // A rejected Google→email signup signs the session back out. Ignore a
      // stale signedIn that finishes after that sign-out.
      if (_authService.currentSession == null) return;

      // signInWithEmail / loginWithGoogle already hydrated _user; repeating
      // getCurrentUser here duplicates getUser + profile queries on the UI path.
      if (authEvent == AuthChangeEvent.signedIn) {
        final sessionUserId = _authService.currentSession?.user.id;
        if (_user != null &&
            sessionUserId != null &&
            _user!.id == sessionUserId) {
          return;
        }
      }

      final currentUser = await _authService.getCurrentUser();
      if (currentUser == null || _authService.currentSession == null) return;

      if (currentUser.sessionBlockMessage != null) {
        await _authService.signOut();
        _user = null;
        await _clearSession();
        notifyListeners();
        return;
      }

      final recoveryInProgress =
          _passwordRecoveryActive || _prefs.isPasswordRecoveryPending;
      if (recoveryInProgress) {
        await _activatePasswordRecovery();
        _user = currentUser;
        notifyListeners();
        return;
      }

      if (!shouldPersistAuthSession(
        passwordRecoveryActive: _passwordRecoveryActive,
        passwordRecoveryPending: _prefs.isPasswordRecoveryPending,
      )) {
        return;
      }

      _user = currentUser;
      _syncActiveAccount(
        currentUser,
        restoreFromPrefs: authEvent == AuthChangeEvent.signedIn,
      );
      await _saveSession(currentUser);
      notifyListeners();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Sign In
  // ─────────────────────────────────────────────────────────────────────────

  /// Signs in with email and password after the user has accepted the legal
  /// documents.
  ///
  /// Returns [EmailLoginResult.success] or a safe failure message from the mapper.
  Future<EmailLoginResult> loginWithEmail({
    required String email,
    required String password,
    required LegalConsent consent,
    required String turnstileToken,
    LoginPortal loginPortal = LoginPortal.app,
  }) async {
    _isLoading = true;
    _resolvingTrustedDevice = true;
    await _setEmailOtpPending(true);
    notifyListeners();

    try {
      final result = await _authService.signInWithEmail(
        email: email,
        password: password,
        consent: consent,
        turnstileToken: turnstileToken,
        loginPortal: loginPortal,
      );

      if (!result.success || result.user == null) {
        await _setEmailOtpPending(false);
        return EmailLoginResult.failure(
          result.errorMessage ?? emailLoginGenericFallbackMessage,
          retryAfterSeconds: result.retryAfterSeconds,
        );
      }

      final blocked = result.user!.sessionBlockMessage;
      if (blocked != null) {
        await _authService.signOut();
        await _setEmailOtpPending(false);
        return EmailLoginResult.failure(blocked);
      }

      _user = result.user;
      _syncActiveAccount(_user!, restoreFromPrefs: true);
      await _saveSession(_user!);

      var serverTrusted = false;
      try {
        final deviceToken = await _trustedDevices.currentToken();
        serverTrusted = await _authService.isTrustedDevice(
          deviceToken: deviceToken,
        );
      } catch (_) {
        debugPrint('AuthProvider.loginWithEmail trusted-device check failed');
        serverTrusted = false;
      }

      // TEMP: _bypassOtp forces the skip (debug builds only), never for admins.
      final skipOtp =
          (_bypassOtp && !result.user!.isAdmin) ||
          shouldSkipEmailOtp(
            passwordAccepted: true,
            serverTrusted: serverTrusted,
          );
      if (skipOtp) {
        await _setEmailOtpPending(false);
      } else {
        await _setEmailOtpPending(true);
        await sendEmailOtp();
      }
      return EmailLoginResult.success();
    } finally {
      _resolvingTrustedDevice = false;
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Signs in with Google after the user has accepted the legal documents.
  ///
  /// Returns an error message on failure, or `null` on success.
  /// Sends a password reset email. Does not reveal whether the address exists.
  Future<String?> requestPasswordReset({
    required String email,
    required String turnstileToken,
  }) async {
    _isLoading = true;
    notifyListeners();
    try {
      return await _authService.requestPasswordReset(
        email: email,
        turnstileToken: turnstileToken,
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Updates the password from a recovery session, then signs out so the user
  /// must sign in again (including email OTP when required).
  Future<String?> completePasswordReset({required String password}) async {
    _isLoading = true;
    notifyListeners();
    try {
      final error = await _authService.updatePasswordForRecovery(
        password: password,
      );
      if (error != null) return error;

      await _terminatePasswordRecoverySession(clearPendingFlag: true);
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Called as soon as a recovery deep link is accepted (before OTP exchange).
  Future<void> markPasswordRecoveryPending() => _activatePasswordRecovery();

  /// Abandons recovery: signs out Supabase and clears recovery flags/cache.
  Future<void> cancelPasswordRecovery() async {
    if (!_passwordRecoveryActive && !_prefs.isPasswordRecoveryPending) {
      return;
    }
    await _terminatePasswordRecoverySession(clearPendingFlag: true);
    notifyListeners();
  }

  /// Clears recovery flags when link exchange failed before a session existed.
  Future<void> abandonPasswordRecoveryLinkAttempt() async {
    if (_authService.currentSession != null) {
      await cancelPasswordRecovery();
      return;
    }
    _passwordRecoveryActive = false;
    await _setPasswordRecoveryPending(false);
    notifyListeners();
  }

  Future<void> _activatePasswordRecovery() async {
    _passwordRecoveryActive = true;
    await _setEmailOtpPending(false);
    await _setPasswordRecoveryPending(true);
  }

  Future<void> _setPasswordRecoveryPending(bool value) async {
    await _prefs.setPasswordRecoveryPending(value);
  }

  Future<void> _terminatePasswordRecoverySession({
    required bool clearPendingFlag,
  }) async {
    _passwordRecoveryActive = false;
    if (clearPendingFlag) {
      await _setPasswordRecoveryPending(false);
    }
    await _authService.signOut();
    _user = null;
    _emailOtpPending = false;
    _activeAccount = AccountMode.buyer;
    await _clearSession();
  }

  Future<String?> loginWithGoogle({required LegalConsent consent}) async {
    _isLoading = true;
    notifyListeners();

    final result = await _authService.signInWithGoogle(consent: consent);

    if (!result.success) {
      _isLoading = false;
      notifyListeners();
      return result.errorMessage;
    }

    final blocked = result.user?.sessionBlockMessage;
    if (blocked != null) {
      await _authService.signOut();
      _isLoading = false;
      notifyListeners();
      return blocked;
    }

    _user = result.user;
    _syncActiveAccount(_user!, restoreFromPrefs: true);
    await _saveSession(_user!);
    await _setEmailOtpPending(false);

    _isLoading = false;
    notifyListeners();
    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Sign Up
  // ─────────────────────────────────────────────────────────────────────────

  /// Creates a new account with email and password.
  ///
  /// Returns the auth result, including whether email verification is needed.
  Future<AuthResult> signUpWithEmail({
    required String email,
    required String password,
    required String name,
    required LegalConsent consent,
  }) async {
    _isLoading = true;
    notifyListeners();

    final result = await _authService.signUpWithEmail(
      email: email,
      password: password,
      name: name,
      consent: consent,
    );

    if (!result.success) {
      _user = null;
      await _setEmailOtpPending(false);
      await _clearSession();
      _isLoading = false;
      notifyListeners();
      return result;
    }

    if (!result.requiresEmailVerification && result.user == null) {
      await _setEmailOtpPending(false);
      _isLoading = false;
      notifyListeners();
      return AuthResult.failure('Something went wrong. Please try again.');
    }

    // TEMP: with the OTP bypass on, sign-up never enters the OTP step.
    final needsOtp = result.requiresEmailOtp && !_bypassOtp;

    if (result.requiresEmailVerification) {
      // Supabase withheld the session pending confirmation, so the app must
      // not treat the account as signed in.
      _user = null;
      await _clearSession();
    } else {
      _user = result.user;
      if (_user != null) {
        _syncActiveAccount(_user!, restoreFromPrefs: true);
        await _saveSession(_user!);
        if (needsOtp) {
          await _setEmailOtpPending(true);
        }
      }
    }

    _isLoading = false;
    notifyListeners();
    if (needsOtp && _user != null) {
      await sendEmailOtp();
    }
    return result;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Sign Out
  // ─────────────────────────────────────────────────────────────────────────

  /// Clears the session and logs the user out.
  ///
  /// A normal logout keeps the trusted-device grant, so the next email
  /// sign-in on this install can skip OTP until the server expiry.
  /// [forgetDevice] revokes that grant first and replaces the local token.
  /// If revocation fails, the session stays signed in.
  Future<String?> logout({bool forgetDevice = false}) async {
    final revokeTrust = forgetDevice && usesEmailPasswordAuth;
    if (revokeTrust) {
      final error = await _forgetTrustedDevice();
      if (error != null) return error;
    }

    final wasAdmin = _user?.isAdmin ?? false;

    _isLoading = true;
    notifyListeners();

    if (wasAdmin) {
      try {
        await _authService.recordAdminLogoutAudit();
      } catch (_) {
        debugPrint('AuthProvider.logout admin audit failed');
      }
    }

    await _authService.signOut();
    _user = null;
    _emailOtpPending = false;
    _activeAccount = AccountMode.buyer;
    await _clearSession();

    _isLoading = false;
    notifyListeners();
    return null;
  }

  Future<String?> _forgetTrustedDevice() async {
    _isLoading = true;
    notifyListeners();
    try {
      final existing = await _trustedDevices.storedToken();
      if (existing != null) {
        final error = await _authService.revokeTrustedDevice(
          deviceToken: existing,
        );
        if (error != null) return error;
      }
      await _trustedDevices.rotate();
      return null;
    } catch (_) {
      debugPrint('AuthProvider.logout forget device failed');
      return 'Could not forget this device. Please try again.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Profile Updates
  // ─────────────────────────────────────────────────────────────────────────

  /// Persists the user-editable subset of the profile.
  ///
  /// `role`, `trust_score` and `rating_average` are deliberately absent. They
  /// are owned by the database — `trg_users_column_guard` reverts any client
  /// write to them — so sending them would silently do nothing.
  ///
  /// An empty username is sent as `null`. `users.username` is UNIQUE, and an
  /// empty string is a real value, so the second account to save a blank
  /// username would collide; NULLs do not.
  Future<void> updateCurrentUser(AuthUser updatedUser) async {
    _user = updatedUser;
    final username = updatedUser.username.trim();
    await _authService.updateUserRecord(updatedUser.id, {
      'full_name': updatedUser.name,
      'username': username.isEmpty ? null : username,
      'email': updatedUser.email,
      'phone_number': updatedUser.phone,
      'avatar': updatedUser.avatarUrl.isEmpty ? null : updatedUser.avatarUrl,
      if (updatedUser.bio != null) 'bio': updatedUser.bio,
      if (updatedUser.location.isNotEmpty) 'location': updatedUser.location,
    });
    await _saveSession(_user!);
    notifyListeners();
  }

  Future<void> updateProfileData({
    String? name,
    String? username,
    String? email,
    String? phone,
    String? avatarUrl,
    String? shopName,
    String? shopBio,
  }) async {
    if (_user != null) {
      _user = _user!.copyWith(
        name: name ?? _user!.name,
        username: username ?? _user!.username,
        email: email ?? _user!.email,
        phone: phone ?? _user!.phone,
        avatarUrl: avatarUrl ?? _user!.avatarUrl,
        shopName: shopName ?? _user!.shopName,
        shopBio: shopBio ?? _user!.shopBio,
      );
      await _saveSession(_user!);
      notifyListeners();
    }
  }

  Future<void> reloadUser() async {
    final currentUser = await _authService.getCurrentUser();
    if (currentUser == null) return;

    if (currentUser.sessionBlockMessage != null) {
      await _authService.signOut();
      _user = null;
      await _clearSession();
      notifyListeners();
      return;
    }

    _user = currentUser;
    _syncActiveAccount(currentUser, restoreFromPrefs: false);
    await _saveSession(currentUser);
    notifyListeners();
  }

  /// Sends a login/signup email OTP through the Gmail SMTP Edge Function.
  Future<String?> sendEmailOtp() {
    return _authService.sendEmailOtp();
  }

  /// Confirms the email code, registers this install when a token is
  /// available, then clears the pending-OTP gate.
  Future<String?> verifyEmailOtp({required String token}) async {
    String? deviceToken;
    try {
      deviceToken = await _trustedDevices.currentToken();
    } catch (_) {
      debugPrint('AuthProvider.verifyEmailOtp device token unavailable');
    }
    final error = await _authService.verifyEmailOtp(
      token: token,
      deviceToken: deviceToken,
      platform: deviceToken == null
          ? null
          : trustedDevicePlatformLabel(defaultTargetPlatform),
    );
    if (error == null) {
      await _setEmailOtpPending(false);
      if (_user?.isAdmin ?? false) {
        try {
          await _authService.recordAdminLoginCompletedAudit();
        } catch (_) {
          debugPrint('AuthProvider.verifyEmailOtp admin audit failed');
        }
      }
    }
    return error;
  }

  /// Install-scoped token for bid-risk signals (hashed server-side).
  Future<String?> deviceInstallTokenForRisk() async {
    try {
      final token = await _trustedDevices.currentToken();
      if (isDeviceTrustToken(token)) return token;
    } catch (e) {
      debugPrint('AuthProvider.deviceInstallTokenForRisk: $e');
    }
    return null;
  }

  /// Sends a phone OTP through the server-side FMCSMS function.
  Future<PhoneOtpResult> sendPhoneOtp(String phone) {
    return _authService.sendPhoneOtp(phone);
  }

  /// Confirms the SMS code, then reloads the profile so `isPhoneVerified` updates.
  Future<PhoneOtpResult> verifyPhoneOtp({
    required String phone,
    required String token,
    String? deviceToken,
    String? platform,
  }) async {
    final result = await _authService.verifyPhoneOtp(
      phone: phone,
      token: token,
      deviceToken: deviceToken,
      platform: platform,
    );
    if (result.isOk) await reloadUser();
    return result;
  }

  /// Lets a rejected applicant fill the form again. The rejected row stays
  /// in the database; a new pending application can be inserted.
  void prepareVerificationReapply() {
    if (_user == null) return;
    _user = _user!.copyWith(
      verificationStatus: 'none',
      verificationRejectionReason: null,
    );
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Session Persistence (SharedPreferences cache for fast cold-start)
  // ─────────────────────────────────────────────────────────────────────────

  void _syncActiveAccount(AuthUser user, {required bool restoreFromPrefs}) {
    final sellerBlocked =
        user.accountStatus != 'active' ||
        (user.isSeller && user.trustLevel?.trim() == 'Banned');
    _activeAccount = resolveAccountMode(
      hasSellerAccess: user.hasSellerAccess,
      isAdmin: user.isAdmin,
      savedMode: _prefs.activeAccountFor(user.id),
      currentMode: _activeAccount,
      restoreFromPrefs: restoreFromPrefs,
      sellerWorkspaceBlocked: sellerBlocked,
    );
  }

  Future<void> _saveSession(AuthUser user) async {
    await _prefs.setLoggedIn(true);
    await _prefs.setUserRole(user.role.dbValue);
    await _prefs.setUsername(user.username);
    await _prefs.setUserId(user.id);
    await _prefs.setDisplayName(displayName ?? user.displayName);
    if (user.hasSellerAccess && !user.isAdmin) {
      await _prefs.setActiveAccount(userId: user.id, mode: _activeAccount.name);
    }
  }

  Future<void> _setEmailOtpPending(bool value) async {
    _emailOtpPending = value;
    await _prefs.setEmailOtpPending(value);
  }

  Future<void> _clearSession() async {
    _emailOtpPending = false;
    await _prefs.clearAuthSession();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}
