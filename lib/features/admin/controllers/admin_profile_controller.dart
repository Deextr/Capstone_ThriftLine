import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/utils/validators.dart';
import '../../../features/auth/data/auth_service.dart';
import '../../../models/enums.dart';
import '../../../providers/auth_provider.dart';

class AdminProfileController extends ChangeNotifier {
  AdminProfileController({
    required SupabaseService supabase,
    required AuthProvider auth,
    required AuthService authService,
  }) : _supabase = supabase,
       _auth = auth,
       _authService = authService {
    _name = auth.user?.name ?? '';
  }

  final SupabaseService _supabase;
  final AuthProvider _auth;
  final AuthService _authService;

  static const int maxAvatarBytes = 5 * 1024 * 1024;
  static const Set<String> allowedAvatarMimes = {
    'image/jpeg',
    'image/jpg',
    'image/png',
    'image/webp',
  };

  String _name = '';
  Uint8List? _pendingAvatarBytes;
  String? _pendingAvatarPreviewPath;
  String? _pendingAvatarContentType;
  bool _removeAvatarOnSave = false;

  bool _isSavingProfile = false;
  bool _isUpdatingPassword = false;
  String? _profileError;
  String? _passwordError;
  String? _profileSuccess;
  String? _passwordSuccess;

  String get name => _name;
  String get email => _auth.user?.email ?? '';
  String get avatarUrl =>
      _removeAvatarOnSave ? '' : (_auth.user?.avatarUrl ?? '');
  bool get usesEmailPassword => _auth.user?.usesEmailPasswordAuth ?? false;
  bool get isSavingProfile => _isSavingProfile;
  bool get isUpdatingPassword => _isUpdatingPassword;
  String? get profileError => _profileError;
  String? get passwordError => _passwordError;
  String? get profileSuccess => _profileSuccess;
  String? get passwordSuccess => _passwordSuccess;
  bool get hasPendingAvatar => _pendingAvatarBytes != null;
  bool get willRemoveAvatar => _removeAvatarOnSave;
  bool get hasAvatar =>
      !_removeAvatarOnSave &&
      (_auth.user?.avatarUrl.trim().isNotEmpty ?? false);

  String get roleLabel {
    final role = _auth.user?.role;
    return switch (role) {
      UserRole.superAdmin => 'Superadmin',
      UserRole.admin => 'Administrator',
      _ => role?.label ?? 'Administrator',
    };
  }

  String? get pendingAvatarPreviewPath => _pendingAvatarPreviewPath;
  Uint8List? get pendingAvatarBytes => _pendingAvatarBytes;

  void setName(String value) {
    _name = value;
    _profileSuccess = null;
    notifyListeners();
  }

  void clearErrors() {
    _profileError = null;
    _passwordError = null;
    _profileSuccess = null;
    _passwordSuccess = null;
    notifyListeners();
  }

  void discardPendingAvatar() {
    _pendingAvatarBytes = null;
    _pendingAvatarPreviewPath = null;
    _pendingAvatarContentType = null;
    _removeAvatarOnSave = false;
    notifyListeners();
  }

  void markAvatarForRemoval() {
    _pendingAvatarBytes = null;
    _pendingAvatarPreviewPath = null;
    _pendingAvatarContentType = null;
    _removeAvatarOnSave = true;
    _profileError = null;
    _profileSuccess = null;
    notifyListeners();
  }

  Future<void> pickAvatar() async {
    final userId = _supabase.currentUser?.id;
    if (userId == null) return;

    final picker = ImagePicker();
    final xfile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (xfile == null) return;

    final mime = _resolveContentType(xfile);
    if (!allowedAvatarMimes.contains(mime)) {
      _profileError = 'Use a JPEG, PNG, or WebP image.';
      _profileSuccess = null;
      notifyListeners();
      return;
    }

    final bytes = await xfile.readAsBytes();
    if (bytes.length > maxAvatarBytes) {
      _profileError = 'Choose an image smaller than 5 MB.';
      _profileSuccess = null;
      notifyListeners();
      return;
    }

    _pendingAvatarBytes = bytes;
    _pendingAvatarPreviewPath = xfile.path;
    _pendingAvatarContentType = mime;
    _removeAvatarOnSave = false;
    _profileError = null;
    _profileSuccess = null;
    notifyListeners();
  }

  String _resolveContentType(XFile file) {
    final mime = file.mimeType?.toLowerCase().trim();
    if (mime != null && mime.isNotEmpty) {
      return mime == 'image/jpg' ? 'image/jpeg' : mime;
    }
    final name = file.name.toLowerCase();
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  String _extensionFor(String contentType) {
    return switch (contentType) {
      'image/png' => 'png',
      'image/webp' => 'webp',
      _ => 'jpg',
    };
  }

  Future<String?> saveProfile() async {
    final userId = _supabase.currentUser?.id ?? _auth.user?.id;
    if (userId == null) {
      return 'You need to be signed in to update your profile.';
    }

    final nameError = Validators.adminFullName(_name);
    if (nameError != null) {
      _profileError = nameError;
      _profileSuccess = null;
      notifyListeners();
      return _profileError;
    }

    final trimmedName = Validators.normalizeFullName(_name);

    _isSavingProfile = true;
    _profileError = null;
    _profileSuccess = null;
    notifyListeners();

    try {
      String? avatarUrl = _auth.user?.avatarUrl;
      if (_removeAvatarOnSave) {
        avatarUrl = '';
      } else if (_pendingAvatarBytes != null) {
        final contentType = _pendingAvatarContentType ?? 'image/jpeg';
        final path = '$userId/avatar.${_extensionFor(contentType)}';
        await _supabase.client.storage
            .from('avatars')
            .uploadBinary(
              path,
              _pendingAvatarBytes!,
              fileOptions: FileOptions(contentType: contentType, upsert: true),
            );
        final url = _supabase.client.storage.from('avatars').getPublicUrl(path);
        avatarUrl = '$url?t=${DateTime.now().millisecondsSinceEpoch}';
      }

      await _supabase.updateUserProfile(
        userId: userId,
        data: {
          'full_name': trimmedName,
          'avatar': (avatarUrl == null || avatarUrl.isEmpty) ? null : avatarUrl,
          'updated_at': DateTime.now().toIso8601String(),
        },
      );

      await _auth.updateProfileData(
        name: trimmedName,
        avatarUrl: avatarUrl ?? '',
      );

      _pendingAvatarBytes = null;
      _pendingAvatarPreviewPath = null;
      _pendingAvatarContentType = null;
      _removeAvatarOnSave = false;
      _name = trimmedName;
      _profileSuccess = 'Profile updated.';
      return null;
    } catch (e) {
      debugPrint('AdminProfileController.saveProfile error: $e');
      _profileError = 'Could not update your profile. Please try again.';
      return _profileError;
    } finally {
      _isSavingProfile = false;
      notifyListeners();
    }
  }

  Future<String?> updatePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {
    final email = _auth.user?.email ?? '';
    if (email.isEmpty) {
      return 'Your email is unavailable. Sign in again and retry.';
    }
    if (_isUpdatingPassword) return _passwordError;

    if (currentPassword.isEmpty) {
      _passwordError = 'Enter your current password.';
      _passwordSuccess = null;
      notifyListeners();
      return _passwordError;
    }

    final newError = Validators.adminPassword(newPassword);
    if (newError != null) {
      _passwordError = newError;
      _passwordSuccess = null;
      notifyListeners();
      return newError;
    }

    if (newPassword == currentPassword) {
      _passwordError =
          'Choose a new password that is different from your current one.';
      _passwordSuccess = null;
      notifyListeners();
      return _passwordError;
    }

    final confirmError = Validators.confirmPassword(
      confirmPassword,
      newPassword,
    );
    if (confirmError != null) {
      _passwordError = confirmError;
      _passwordSuccess = null;
      notifyListeners();
      return confirmError;
    }

    _isUpdatingPassword = true;
    _passwordError = null;
    _passwordSuccess = null;
    notifyListeners();

    final error = await _authService.updatePasswordInSession(
      email: email,
      currentPassword: currentPassword,
      newPassword: newPassword,
    );

    _isUpdatingPassword = false;
    if (error != null) {
      _passwordError = error;
      notifyListeners();
      return error;
    }
    _passwordSuccess = 'Password updated.';
    notifyListeners();
    return null;
  }
}
