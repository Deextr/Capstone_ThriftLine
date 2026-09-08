import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthState, AuthChangeEvent;

import '../core/services/shared_preferences_service.dart';
import '../features/auth/data/auth_service.dart';
import '../features/auth/data/auth_result.dart';
import '../features/auth/domain/account_mode.dart';
import '../features/auth/domain/auth_user.dart';
import '../features/auth/domain/legal_documents.dart';
import '../models/enums.dart';

/// Router-facing gate: a restored session is not enough while email OTP is
/// still outstanding.
bool authIsFullyAuthenticated({
  required bool hasSession,
  required bool emailOtpPending,
}) => hasSession && !emailOtpPending;

/// Manages authentication state, session persistence, and role detection.
///
/// Wraps [AuthService] (Supabase) and caches minimal session data
/// in [SharedPreferencesService] for fast cold-start restoration.
class AuthProvider extends ChangeNotifier {
  AuthProvider(this._prefs, this._authService);

  final SharedPreferencesService _prefs;
  final AuthService _authService;

  AuthUser? _user;
  bool _isLoading = false;
  bool _isInitialized = false;
  bool _emailOtpPending = false;
  AccountMode _activeAccount = AccountMode.buyer;

  StreamSubscription? _authSubscription;

  AuthUser? get user => _user;
  bool get isLoading => _isLoading;
  bool get isInitialized => _isInitialized;
  bool get isAuthenticated => _user != null;
  bool get isEmailOtpPending => _emailOtpPending;

  /// Session exists and the email OTP step is not still outstanding.
  bool get isFullyAuthenticated => authIsFullyAuthenticated(
    hasSession: isAuthenticated,
    emailOtpPending: _emailOtpPending,
  );

  /// Current Buyer/Seller workspace. Independent of `users.role`.
  AccountMode get activeAccount => _activeAccount;

  bool get hasSellerAccess => _user?.hasSellerAccess ?? false;

  bool get canSwitchAccounts =>
      authCanSwitchAccounts(hasSellerAccess: hasSellerAccess, isAdmin: isAdmin);

  bool get isBuyer => !isAdmin && _activeAccount == AccountMode.buyer;
  bool get isSeller => !isAdmin && _activeAccount == AccountMode.seller;
  bool get isAdmin => _user?.isAdmin ?? false;
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
    notifyListeners();
  }

  /// Restores a session from Supabase (auto-login via persisted JWT).
  ///
  /// Called once at app startup from `main()`.
  Future<void> init() async {
    try {
      // Supabase SDK automatically restores the session from secure storage.
      final currentUser = await _authService.getCurrentUser();
      if (currentUser != null) {
        _user = currentUser;
        _emailOtpPending = _prefs.isEmailOtpPending;
        _syncActiveAccount(currentUser, restoreFromPrefs: true);
        await _saveSession(currentUser);
      } else {
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
      _activeAccount = AccountMode.buyer;
      await _clearSession();
      notifyListeners();
    } else if (authEvent == AuthChangeEvent.signedIn ||
        authEvent == AuthChangeEvent.tokenRefreshed ||
        authEvent == AuthChangeEvent.userUpdated) {
      // A rejected Google→email signup signs the session back out. Ignore a
      // stale signedIn that finishes after that sign-out.
      if (_authService.currentSession == null) return;
      final currentUser = await _authService.getCurrentUser();
      if (currentUser == null || _authService.currentSession == null) return;
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
  /// Returns an error message on failure, or `null` on success.
  Future<String?> loginWithEmail({
    required String email,
    required String password,
    required LegalConsent consent,
  }) async {
    _isLoading = true;
    await _setEmailOtpPending(true);
    notifyListeners();

    final result = await _authService.signInWithEmail(
      email: email,
      password: password,
      consent: consent,
    );

    if (!result.success) {
      await _setEmailOtpPending(false);
      _isLoading = false;
      notifyListeners();
      return result.errorMessage;
    }

    _user = result.user;
    _syncActiveAccount(_user!, restoreFromPrefs: true);
    await _saveSession(_user!);
    await _setEmailOtpPending(true);

    _isLoading = false;
    notifyListeners();
    await sendEmailOtp();
    return null;
  }

  /// Signs in with Google after the user has accepted the legal documents.
  ///
  /// Returns an error message on failure, or `null` on success.
  Future<String?> loginWithGoogle({required LegalConsent consent}) async {
    _isLoading = true;
    notifyListeners();

    final result = await _authService.signInWithGoogle(consent: consent);

    if (!result.success) {
      _isLoading = false;
      notifyListeners();
      return result.errorMessage;
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
        if (result.requiresEmailOtp) {
          await _setEmailOtpPending(true);
        }
      }
    }

    _isLoading = false;
    notifyListeners();
    if (result.requiresEmailOtp && _user != null) {
      await sendEmailOtp();
    }
    return result;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Sign Out
  // ─────────────────────────────────────────────────────────────────────────

  /// Clears the session and logs the user out.
  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();

    await _authService.signOut();
    _user = null;
    _emailOtpPending = false;
    _activeAccount = AccountMode.buyer;
    await _clearSession();

    _isLoading = false;
    notifyListeners();
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
  }) async {
    if (_user != null) {
      _user = _user!.copyWith(
        name: name ?? _user!.name,
        username: username ?? _user!.username,
        email: email ?? _user!.email,
        phone: phone ?? _user!.phone,
        avatarUrl: avatarUrl ?? _user!.avatarUrl,
      );
      await _saveSession(_user!);
      notifyListeners();
    }
  }

  Future<void> reloadUser() async {
    final currentUser = await _authService.getCurrentUser();
    if (currentUser != null) {
      _user = currentUser;
      _syncActiveAccount(currentUser, restoreFromPrefs: false);
      await _saveSession(currentUser);
      notifyListeners();
    }
  }

  /// Sends a login/signup email OTP through the Gmail SMTP Edge Function.
  Future<String?> sendEmailOtp() {
    return _authService.sendEmailOtp();
  }

  /// Confirms the email code, then clears the pending-OTP gate.
  Future<String?> verifyEmailOtp({required String token}) async {
    final error = await _authService.verifyEmailOtp(token: token);
    if (error == null) await _setEmailOtpPending(false);
    return error;
  }

  /// Sends a phone OTP through the server-side iProgSMS function.
  Future<String?> sendPhoneOtp(String phone) {
    return _authService.sendPhoneOtp(phone);
  }

  /// Confirms the SMS code, then reloads the profile so `isPhoneVerified` updates.
  Future<String?> verifyPhoneOtp({
    required String phone,
    required String token,
  }) async {
    final error = await _authService.verifyPhoneOtp(phone: phone, token: token);
    if (error == null) await reloadUser();
    return error;
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
    _activeAccount = resolveAccountMode(
      hasSellerAccess: user.hasSellerAccess,
      isAdmin: user.isAdmin,
      savedMode: _prefs.activeAccountFor(user.id),
      currentMode: _activeAccount,
      restoreFromPrefs: restoreFromPrefs,
    );
  }

  Future<void> _saveSession(AuthUser user) async {
    await _prefs.setLoggedIn(true);
    await _prefs.setUserRole(user.role.name);
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
