import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthState, AuthChangeEvent;

import '../core/routes/route_names.dart';
import '../core/services/shared_preferences_service.dart';
import '../features/auth/data/auth_service.dart';
import '../features/auth/data/auth_result.dart';
import '../features/auth/domain/auth_user.dart';
import '../models/enums.dart';

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

  StreamSubscription? _authSubscription;

  AuthUser? get user => _user;
  bool get isLoading => _isLoading;
  bool get isInitialized => _isInitialized;
  bool get isAuthenticated => _user != null;

  bool get isBuyer => _user?.isBuyer ?? false;
  bool get isSeller => _user?.isSeller ?? false;
  bool get isAdmin => _user?.isAdmin ?? false;
  UserRole? get role => _user?.role;

  String? get username => _user?.username;
  String? get displayName => _user?.displayName;

  String get homeRoute {
    // Admin route can be added in a future module.
    // For now, admin users go to the buyer home.
    if (isSeller) return RouteNames.sellerHome;
    return RouteNames.buyerHome;
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
      await _clearSession();
      notifyListeners();
    } else if (authEvent == AuthChangeEvent.signedIn ||
        authEvent == AuthChangeEvent.tokenRefreshed ||
        authEvent == AuthChangeEvent.userUpdated) {
      final currentUser = await _authService.getCurrentUser();
      if (currentUser != null) {
        _user = currentUser;
        await _saveSession(currentUser);
        notifyListeners();
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Sign In
  // ─────────────────────────────────────────────────────────────────────────

  /// Signs in with email and password.
  ///
  /// Returns an error message on failure, or `null` on success.
  Future<String?> loginWithEmail({
    required String email,
    required String password,
  }) async {
    _isLoading = true;
    notifyListeners();

    final result = await _authService.signInWithEmail(
      email: email,
      password: password,
    );

    if (!result.success) {
      _isLoading = false;
      notifyListeners();
      return result.errorMessage;
    }

    _user = result.user;
    await _saveSession(_user!);

    _isLoading = false;
    notifyListeners();
    return null;
  }

  /// Signs in with Google.
  ///
  /// Returns an error message on failure, or `null` on success.
  Future<String?> loginWithGoogle() async {
    _isLoading = true;
    notifyListeners();

    final result = await _authService.signInWithGoogle();

    if (!result.success) {
      _isLoading = false;
      notifyListeners();
      return result.errorMessage;
    }

    _user = result.user;
    await _saveSession(_user!);

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
  }) async {
    _isLoading = true;
    notifyListeners();

    final result = await _authService.signUpWithEmail(
      email: email,
      password: password,
      name: name,
    );

    if (!result.success) {
      _isLoading = false;
      notifyListeners();
      return result;
    }

    if (!result.requiresEmailVerification && result.user == null) {
      _isLoading = false;
      notifyListeners();
      return AuthResult.failure('Something went wrong. Please try again.');
    }

    if (result.requiresEmailVerification) {
      _user = null;
      await _clearSession();
    } else {
      _user = result.user;
      if (_user != null) {
        await _saveSession(_user!);
      }
    }

    _isLoading = false;
    notifyListeners();
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
    await _clearSession();

    _isLoading = false;
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Profile Updates
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> updateCurrentUser(AuthUser updatedUser) async {
    _user = updatedUser;
    await _authService.updateUserRecord(updatedUser.id, {
      'full_name': updatedUser.name,
      'username': updatedUser.username,
      'email': updatedUser.email,
      'phone_number': updatedUser.phone,
      'avatar': updatedUser.avatarUrl.isEmpty ? null : updatedUser.avatarUrl,
      'role': updatedUser.role.name,
      'trust_score': updatedUser.trustScore,
      'rating_average': updatedUser.rating,
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
      await _saveSession(currentUser);
      notifyListeners();
    }
  }

  Future<void> submitSellerApplication({
    required String storeName,
    required String address,
    required String region,
  }) async {
    if (_user == null) return;
    final updated = _user!.copyWith(
      shopName: storeName,
      location: '$region, Davao City',
      verificationStatus: 'pending',
      verificationRejectionReason: null,
    );
    await updateCurrentUser(updated);
  }

  Future<void> simulateApproveApplication() async {
    if (_user == null) return;
    final updated = _user!.copyWith(
      role: UserRole.seller,
      isVerified: true,
      verificationStatus: 'approved',
      verificationRejectionReason: null,
    );
    await updateCurrentUser(updated);
  }

  Future<void> simulateRejectApplication(String reason) async {
    if (_user == null) return;
    final updated = _user!.copyWith(
      role: UserRole.buyer,
      isVerified: false,
      verificationStatus: 'rejected',
      verificationRejectionReason: reason,
    );
    await updateCurrentUser(updated);
  }

  Future<void> resetVerificationStatus() async {
    if (_user == null) return;
    final updated = _user!.copyWith(
      verificationStatus: 'none',
      verificationRejectionReason: null,
    );
    await updateCurrentUser(updated);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Session Persistence (SharedPreferences cache for fast cold-start)
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _saveSession(AuthUser user) async {
    await _prefs.setLoggedIn(true);
    await _prefs.setUserRole(user.role.name);
    await _prefs.setUsername(user.username);
    await _prefs.setUserId(user.id);
    await _prefs.setDisplayName(user.displayName);
  }

  Future<void> _clearSession() async {
    await _prefs.clearAuthSession();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}
