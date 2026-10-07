import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/utils/validators.dart';
import '../../../features/auth/data/auth_service.dart';
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

  static const int _maxAvatarBytes = 5 * 1024 * 1024;

  String _name = '';
  Uint8List? _pendingAvatarBytes;
  String? _pendingAvatarPreviewPath;

  bool _isSavingProfile = false;
  bool _isUpdatingPassword = false;
  String? _profileError;
  String? _passwordError;

  String get name => _name;
  String get email => _auth.user?.email ?? '';
  String get avatarUrl => _auth.user?.avatarUrl ?? '';
  bool get usesEmailPassword => _auth.user?.usesEmailPasswordAuth ?? false;
  bool get isSavingProfile => _isSavingProfile;
  bool get isUpdatingPassword => _isUpdatingPassword;
  String? get profileError => _profileError;
  String? get passwordError => _passwordError;
  bool get hasPendingAvatar => _pendingAvatarBytes != null;

  String? get pendingAvatarPreviewPath => _pendingAvatarPreviewPath;
  Uint8List? get pendingAvatarBytes => _pendingAvatarBytes;

  void setName(String value) {
    _name = value;
    notifyListeners();
  }

  void clearErrors() {
    _profileError = null;
    _passwordError = null;
    notifyListeners();
  }

  Future<void> pickAvatar() async {
    final userId = _supabase.currentUser?.id;
    if (userId == null) return;

    final picker = ImagePicker();
    final xfile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (xfile == null) return;

    final bytes = await xfile.readAsBytes();
    if (bytes.length > _maxAvatarBytes) {
      _profileError = 'Choose an image smaller than 5 MB.';
      notifyListeners();
      return;
    }

    _pendingAvatarBytes = bytes;
    _pendingAvatarPreviewPath = xfile.path;
    _profileError = null;
    notifyListeners();
  }

  Future<String?> saveProfile() async {
    final userId = _supabase.currentUser?.id ?? _auth.user?.id;
    if (userId == null) {
      return 'You need to be signed in to update your profile.';
    }

    final trimmedName = _name.trim();
    if (trimmedName.isEmpty) {
      _profileError = 'Enter your name.';
      notifyListeners();
      return _profileError;
    }

    _isSavingProfile = true;
    _profileError = null;
    notifyListeners();

    try {
      String? avatarUrl = _auth.user?.avatarUrl;
      if (_pendingAvatarBytes != null) {
        final path = '$userId/avatar.jpg';
        await _supabase.client.storage
            .from('avatars')
            .uploadBinary(
              path,
              _pendingAvatarBytes!,
              fileOptions: const FileOptions(
                contentType: 'image/jpeg',
                upsert: true,
              ),
            );
        final url = _supabase.client.storage.from('avatars').getPublicUrl(path);
        avatarUrl = '$url?t=${DateTime.now().millisecondsSinceEpoch}';
      }

      await _supabase.updateUserProfile(
        userId: userId,
        data: {
          'full_name': trimmedName,
          if (avatarUrl != null && avatarUrl.isNotEmpty) 'avatar': avatarUrl,
          'updated_at': DateTime.now().toIso8601String(),
        },
      );

      await _auth.updateProfileData(name: trimmedName, avatarUrl: avatarUrl);

      _pendingAvatarBytes = null;
      _pendingAvatarPreviewPath = null;
      _name = trimmedName;
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

    final confirmError = Validators.confirmPassword(
      confirmPassword,
      newPassword,
    );
    if (confirmError != null) {
      _passwordError = confirmError;
      notifyListeners();
      return confirmError;
    }

    _isUpdatingPassword = true;
    _passwordError = null;
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
    notifyListeners();
    return null;
  }
}
