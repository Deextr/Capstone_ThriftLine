import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/utils/ph_phone.dart';
import '../../../features/auth/domain/account_mode.dart';
import '../../../models/user_model.dart';
import '../../../providers/auth_provider.dart';

class ProfileController extends ChangeNotifier {
  ProfileController({
    required SupabaseService supabaseService,
    AuthProvider? authProvider,
  }) : _supabaseService = supabaseService,
       _authProvider = authProvider;

  final SupabaseService _supabaseService;
  final AuthProvider? _authProvider;

  UserModel? _currentUser;
  String? _shopName;
  String? _shopBio;
  String? _sellerAvatarUrl;
  bool _isLoading = false;
  bool _isSaving = false;
  bool _isUploadingAvatar = false;
  String? _errorMessage;
  String? _successMessage;

  UserModel? get currentUser => _currentUser;
  bool get isSellerMode => _authProvider?.activeAccount == AccountMode.seller;
  String? get shopName => _shopName;
  String? get shopBio => _shopBio;
  String get displayAvatarUrl {
    if (isSellerMode && (_sellerAvatarUrl?.trim().isNotEmpty ?? false)) {
      return _sellerAvatarUrl!;
    }
    return _currentUser?.avatarUrl ?? _authProvider?.user?.avatarUrl ?? '';
  }

  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  bool get isUploadingAvatar => _isUploadingAvatar;
  String? get errorMessage => _errorMessage;
  String? get successMessage => _successMessage;

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

      if (isSellerMode) {
        final sellerRow = await _supabaseService.client
            .from('seller_profiles')
            .select('shop_name, shop_bio, shop_avatar_url')
            .eq('seller_id', targetId)
            .maybeSingle();
        if (sellerRow != null) {
          _shopName = sellerRow['shop_name'] as String?;
          _shopBio = sellerRow['shop_bio'] as String?;
          _sellerAvatarUrl = sellerRow['shop_avatar_url'] as String?;
        }
      }
    } catch (e) {
      _errorMessage = 'Failed to load profile: ${e.toString()}';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> checkUsernameAvailability(String username) async {
    final currentUserId =
        _supabaseService.currentUser?.id ?? _currentUser?.id ?? '';
    if (currentUserId.isEmpty) return true;

    try {
      return await _supabaseService.checkUsernameAvailability(
        username,
        currentUserId,
      );
    } catch (e) {
      return false;
    }
  }

  bool isValidUsernameFormat(String username) {
    if (username.isEmpty) return false;
    final regex = RegExp(r'^[a-zA-Z0-9]+$');
    return regex.hasMatch(username);
  }

  Future<bool> updateProfile({
    required String fullName,
    required String username,
    required String phone,
    String? shopBio,
  }) async {
    final currentUserId = _supabaseService.currentUser?.id ?? _currentUser?.id;
    if (currentUserId == null) {
      _errorMessage = 'Authentication required to update profile.';
      notifyListeners();
      return false;
    }

    _errorMessage = null;
    _successMessage = null;

    final trimmedName = fullName.trim();
    final trimmedUsername = username.trim();
    final trimmedPhone = phone.trim();
    final authUser = _authProvider?.user;
    final authPhone = normalizePhMobile(authUser?.phone);

    if (trimmedName.isEmpty) {
      _errorMessage = isSellerMode
          ? 'Shop name cannot be empty.'
          : 'Full Name cannot be empty.';
      notifyListeners();
      return false;
    }

    if (trimmedUsername.isEmpty) {
      _errorMessage = 'Username cannot be empty.';
      notifyListeners();
      return false;
    }

    if (!isValidUsernameFormat(trimmedUsername)) {
      _errorMessage =
          'Username must contain letters and numbers only, with no spaces or special characters.';
      notifyListeners();
      return false;
    }

    if (trimmedPhone.isNotEmpty) {
      final phoneError = phMobile09EditProfileValidationError(trimmedPhone);
      if (phoneError != null) {
        _errorMessage = phoneError;
        notifyListeners();
        return false;
      }
    }

    _isSaving = true;
    notifyListeners();

    try {
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

      if (isSellerMode) {
        await _supabaseService.client
            .from('seller_profiles')
            .update({
              'shop_name': trimmedName,
              if (shopBio != null) 'shop_bio': shopBio.trim(),
            })
            .eq('seller_id', currentUserId);
        _shopName = trimmedName;
        if (shopBio != null) _shopBio = shopBio.trim();
      } else {
        await _supabaseService.updateUserProfile(
          userId: currentUserId,
          data: {
            'full_name': trimmedName,
            'updated_at': DateTime.now().toIso8601String(),
          },
        );
      }

      // `phone_number` / `is_phone_verified` are updated only by verify-phone-otp.
      final userUpdate = <String, dynamic>{
        'username': trimmedUsername,
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (!isSellerMode) {
        userUpdate['full_name'] = trimmedName;
      }

      await _supabaseService.updateUserProfile(
        userId: currentUserId,
        data: userUpdate,
      );

      final syncedPhone = authPhone ?? _currentUser?.phone;

      _currentUser =
          (_currentUser ??
                  UserModel(
                    id: currentUserId,
                    name: trimmedName,
                    username: trimmedUsername,
                    email: _authProvider?.user?.email ?? '',
                    phone: syncedPhone,
                    role:
                        _authProvider?.user?.role ??
                        UserModel.fromJson({}).role,
                    createdAt: DateTime.now(),
                  ))
              .copyWith(
                name: isSellerMode
                    ? (_currentUser?.name ?? trimmedName)
                    : trimmedName,
                username: trimmedUsername,
                phone: syncedPhone,
              );

      if (_authProvider != null) {
        await _authProvider.updateProfileData(
          name: isSellerMode ? _authProvider.user?.name : trimmedName,
          username: trimmedUsername,
          phone: syncedPhone,
          shopName: isSellerMode ? trimmedName : null,
          shopBio: isSellerMode && shopBio != null ? shopBio.trim() : null,
        );
      }

      _successMessage = 'Profile updated successfully!';
      _isSaving = false;
      notifyListeners();
      return true;
    } on PostgrestException catch (e) {
      _isSaving = false;
      if (e.message.contains('unique') ||
          e.message.contains('duplicate') ||
          e.code == '23505') {
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

  Future<void> pickAndUploadAvatar() async {
    final currentUserId = _supabaseService.currentUser?.id ?? _currentUser?.id;
    if (currentUserId == null) return;

    final picker = ImagePicker();
    final xfile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (xfile == null) return;

    _isUploadingAvatar = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final Uint8List bytes = await xfile.readAsBytes();
      final path = isSellerMode
          ? '$currentUserId/seller/avatar.jpg'
          : '$currentUserId/avatar.jpg';

      await _supabaseService.client.storage
          .from('avatars')
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: 'image/jpeg', upsert: true),
          );

      final url = _supabaseService.client.storage
          .from('avatars')
          .getPublicUrl(path);
      final bustUrl = '$url?t=${DateTime.now().millisecondsSinceEpoch}';

      if (isSellerMode) {
        await _supabaseService.client
            .from('seller_profiles')
            .update({'shop_avatar_url': bustUrl})
            .eq('seller_id', currentUserId);
        _sellerAvatarUrl = bustUrl;
        await _authProvider?.updateSellerAvatarUrl(bustUrl);
      } else {
        await _supabaseService.updateUserProfile(
          userId: currentUserId,
          data: {
            'avatar': bustUrl,
            'updated_at': DateTime.now().toIso8601String(),
          },
        );
        if (_currentUser != null) {
          _currentUser = _currentUser!.copyWith(avatarUrl: bustUrl);
        }
        await _authProvider?.updateProfileData(avatarUrl: bustUrl);
      }

      _successMessage = 'Avatar updated!';
    } catch (e) {
      _errorMessage = 'Failed to upload avatar: $e';
    } finally {
      _isUploadingAvatar = false;
      notifyListeners();
    }
  }

  void clearMessages() {
    _errorMessage = null;
    _successMessage = null;
    notifyListeners();
  }
}
