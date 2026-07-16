import 'package:flutter/foundation.dart';

import '../core/routes/route_names.dart';
import '../core/services/shared_preferences_service.dart';
import '../features/auth/data/auth_service.dart';
import '../features/auth/domain/auth_user.dart';
import '../models/enums.dart';

/// Manages authentication state, session persistence, and role detection.
class AuthProvider extends ChangeNotifier {
  AuthProvider(this._prefs, this._authService);

  final SharedPreferencesService _prefs;
  final AuthService _authService;

  AuthUser? _user;
  bool _isLoading = false;
  bool _isInitialized = false;

  AuthUser? get user => _user;
  bool get isLoading => _isLoading;
  bool get isInitialized => _isInitialized;
  bool get isAuthenticated => _user != null;

  bool get isBuyer => _user?.isBuyer ?? false;
  bool get isSeller => _user?.isSeller ?? false;
  UserRole? get role => _user?.role;

  String? get username => _user?.username;
  String? get displayName => _user?.displayName;

  String get homeRoute =>
      isSeller ? RouteNames.sellerHome : RouteNames.buyerHome;

  /// Restores a persisted session from SharedPreferences (auto login).
  Future<void> init() async {
    if (_prefs.isLoggedIn) {
      final storedUsername = _prefs.username;
      final storedRole = _prefs.userRole;

      if (storedUsername != null && storedRole != null) {
        final restoredUser = _authService.getUserByUsername(storedUsername);
        if (restoredUser != null &&
            restoredUser.role.name == storedRole) {
          _user = restoredUser;
        } else {
          await _clearSession();
        }
      } else {
        await _clearSession();
      }
    }

    _isInitialized = true;
    notifyListeners();
  }

  /// Authenticates with username/password and persists the session on success.
  /// Returns an error message on failure, or null on success.
  Future<String?> login({
    required String username,
    required String password,
  }) async {
    _isLoading = true;
    notifyListeners();

    final result = _authService.authenticate(username, password);

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

  /// Clears the session and logs the user out.
  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();

    _user = null;
    await _clearSession();

    _isLoading = false;
    notifyListeners();
  }

  Future<void> updateCurrentUser(AuthUser updatedUser) async {
    _user = updatedUser;
    _authService.updateUser(updatedUser);
    await _prefs.setUserRole(updatedUser.role.name);
    notifyListeners();
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
}
