import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../../../models/user_model.dart';
import '../../../providers/auth_provider.dart';

class ProfileController extends ChangeNotifier {
  ProfileController({
    required SupabaseService supabaseService,
    AuthProvider? authProvider,
  })  : _supabaseService = supabaseService,
        _authProvider = authProvider;

  final SupabaseService _supabaseService;
  final AuthProvider? _authProvider;

  UserModel? _currentUser;
  bool _isLoading = false;
  bool _isSaving = false;
  String? _errorMessage;
  String? _successMessage;

  UserModel? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get errorMessage => _errorMessage;
  String? get successMessage => _successMessage;

  /// Loads the profile data for [userId] (or currently authenticated user).
  Future<void> loadProfile({String? userId}) async {
    final targetId = userId ?? _supabaseService.currentUser?.id;
    if (targetId == null) {
      _errorMessage = 'No authenticated user found.';
      notifyListeners();
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    _successMessage = null;
    notifyListeners();

    try {
      final profileData = await _supabaseService.fetchUserProfile(targetId);
      if (profileData != null) {
        _currentUser = UserModel.fromJson(profileData);
      } else if (_authProvider?.user != null) {
        final user = _authProvider!.user!;
        _currentUser = UserModel(
          id: user.id,
          name: user.name,
          username: user.username,
          email: user.email,
          phone: user.phone,
          avatarUrl: user.avatarUrl,
          location: user.location,
          role: user.role,
          createdAt: DateTime.now(),
        );
      } else {
        _errorMessage = 'Profile data not found.';
      }
    } catch (e) {
      _errorMessage = 'Failed to load profile: ${e.toString()}';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Checks if [username] is available for the given user.
  Future<bool> checkUsernameAvailability(String username) async {
    final currentUserId = _supabaseService.currentUser?.id ?? _currentUser?.id ?? '';
    if (currentUserId.isEmpty) return true;

    try {
      return await _supabaseService.checkUsernameAvailability(username, currentUserId);
    } catch (e) {
      return false;
    }
  }

  /// Validates format of username: letters and numbers only, no spaces or special characters.
  bool isValidUsernameFormat(String username) {
    if (username.isEmpty) return false;
    final regex = RegExp(r'^[a-zA-Z0-9]+$');
    return regex.hasMatch(username);
  }

  /// Updates profile in Supabase database and syncs with local state.
  Future<bool> updateProfile({
    required String fullName,
    required String username,
    required String email,
    required String phone,
  }) async {
    final currentUserId = _supabaseService.currentUser?.id ?? _currentUser?.id;
    if (currentUserId == null) {
      _errorMessage = 'Authentication required to update profile.';
      notifyListeners();
      return false;
    }

    _errorMessage = null;
    _successMessage = null;

    // 1. Validation
    final trimmedName = fullName.trim();
    final trimmedUsername = username.trim();
    final trimmedEmail = email.trim();
    final trimmedPhone = phone.trim();

    if (trimmedName.isEmpty) {
      _errorMessage = 'Full Name cannot be empty.';
      notifyListeners();
      return false;
    }

    if (trimmedUsername.isEmpty) {
      _errorMessage = 'Username cannot be empty.';
      notifyListeners();
      return false;
    }

    if (!isValidUsernameFormat(trimmedUsername)) {
      _errorMessage = 'Username must contain letters and numbers only, with no spaces or special characters.';
      notifyListeners();
      return false;
    }

    if (trimmedEmail.isEmpty || !trimmedEmail.contains('@')) {
      _errorMessage = 'Please enter a valid email address.';
      notifyListeners();
      return false;
    }

    _isSaving = true;
    notifyListeners();

    try {
      // 2. Uniqueness check if username has changed
      final currentUsername = _currentUser?.username ?? '';
      if (trimmedUsername.toLowerCase() != currentUsername.toLowerCase()) {
        final available = await _supabaseService.checkUsernameAvailability(
          trimmedUsername,
          currentUserId,
        );
        if (!available) {
          _errorMessage = 'Username is already taken.';
          _isSaving = false;
          notifyListeners();
          return false;
        }
      }

      // 3. Supabase update using exact database column names
      final updateData = <String, dynamic>{
        'full_name': trimmedName,
        'username': trimmedUsername,
        'email': trimmedEmail,
        'phone_number': trimmedPhone,
        'updated_at': DateTime.now().toIso8601String(),
      };

      await _supabaseService.updateUserProfile(
        userId: currentUserId,
        data: updateData,
      );

      // 4. Update local UserModel
      _currentUser = (_currentUser ?? UserModel(
        id: currentUserId,
        name: trimmedName,
        username: trimmedUsername,
        email: trimmedEmail,
        phone: trimmedPhone,
        role: _authProvider?.user?.role ?? UserModel.fromJson({}).role,
        createdAt: DateTime.now(),
      )).copyWith(
        name: trimmedName,
        username: trimmedUsername,
        email: trimmedEmail,
        phone: trimmedPhone,
      );

      // 5. Update local AuthProvider state
      if (_authProvider != null) {
        await _authProvider.updateProfileData(
          name: trimmedName,
          username: trimmedUsername,
          email: trimmedEmail,
          phone: trimmedPhone,
        );
      }

      _successMessage = 'Profile updated successfully!';
      _isSaving = false;
      notifyListeners();
      return true;
    } on PostgrestException catch (e) {
      _isSaving = false;
      if (e.message.contains('unique') || e.message.contains('duplicate') || e.code == '23505') {
        _errorMessage = 'Username is already taken.';
      } else {
        _errorMessage = e.message;
      }
      notifyListeners();
      return false;
    } catch (e) {
      _isSaving = false;
      _errorMessage = 'Failed to update profile: ${e.toString()}';
      notifyListeners();
      return false;
    }
  }

  void clearMessages() {
    _errorMessage = null;
    _successMessage = null;
    notifyListeners();
  }
}
