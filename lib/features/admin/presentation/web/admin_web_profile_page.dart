import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/validators.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../controllers/admin_profile_controller.dart';

class AdminWebProfilePage extends StatefulWidget {
  const AdminWebProfilePage({super.key});

  @override
  State<AdminWebProfilePage> createState() => _AdminWebProfilePageState();
}

class _AdminWebProfilePageState extends State<AdminWebProfilePage> {
  final _profileFormKey = GlobalKey<FormState>();
  final _passwordFormKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final profile = context.read<AdminProfileController>();
    _nameController = TextEditingController(text: profile.name);
    _emailController = TextEditingController(text: profile.email);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _saveProfile() async {
    if (!_profileFormKey.currentState!.validate()) return;
    final controller = context.read<AdminProfileController>();
    controller.setName(_nameController.text);
    final error = await controller.saveProfile();
    if (!mounted) return;
    if (error == null) {
      _snack('Profile updated successfully.');
    }
  }

  Future<void> _updatePassword() async {
    if (!_passwordFormKey.currentState!.validate()) return;
    final controller = context.read<AdminProfileController>();
    final error = await controller.updatePassword(
      currentPassword: _currentPasswordController.text,
      newPassword: _newPasswordController.text,
      confirmPassword: _confirmPasswordController.text,
    );
    if (!mounted) return;
    if (error == null) {
      _currentPasswordController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();
      _snack('Password updated successfully.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AdminProfileController>();
    final previewPath = controller.pendingAvatarPreviewPath;

    return ColoredBox(
      color: AppColors.background,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                'Profile information',
                style: AppTypography.subheading.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              Form(
                key: _profileFormKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ProfileAvatarPreview(
                          controller: controller,
                          previewPath: previewPath,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ThriftButton(
                                label: controller.hasPendingAvatar
                                    ? 'Change photo'
                                    : 'Upload photo',
                                variant: ThriftButtonVariant.outline,
                                onPressed: controller.isSavingProfile
                                    ? null
                                    : () async {
                                        await controller.pickAvatar();
                                        if (controller.profileError != null &&
                                            mounted) {
                                          _snack(controller.profileError!);
                                        }
                                      },
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'JPEG up to 5 MB.',
                                style: AppTypography.caption,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (controller.profileError != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        controller.profileError!,
                        style: AppTypography.caption.copyWith(
                          color: AppColors.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    ThriftTextField(
                      label: 'Name',
                      controller: _nameController,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Enter your name.';
                        }
                        return null;
                      },
                      onChanged: controller.setName,
                    ),
                    const SizedBox(height: 16),
                    ThriftTextField(
                      label: 'Email',
                      controller: _emailController,
                      readOnly: true,
                    ),
                    const SizedBox(height: 24),
                    ThriftButton(
                      label: 'Save changes',
                      isLoading: controller.isSavingProfile,
                      onPressed: _saveProfile,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              Text(
                'Password',
                style: AppTypography.subheading.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              if (!controller.usesEmailPassword)
                Text(
                  'Password changes apply to email sign-in accounts. '
                  'Your account uses another sign-in method.',
                  style: AppTypography.caption,
                )
              else ...[
                Form(
                  key: _passwordFormKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ThriftTextField(
                        label: 'Current password',
                        controller: _currentPasswordController,
                        obscureText: true,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Enter your current password.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      ThriftTextField(
                        label: 'New password',
                        controller: _newPasswordController,
                        obscureText: true,
                        validator: Validators.password,
                      ),
                      const SizedBox(height: 16),
                      ThriftTextField(
                        label: 'Confirm new password',
                        controller: _confirmPasswordController,
                        obscureText: true,
                        validator: (value) => Validators.confirmPassword(
                          value,
                          _newPasswordController.text,
                        ),
                      ),
                      if (controller.passwordError != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          controller.passwordError!,
                          style: AppTypography.caption.copyWith(
                            color: AppColors.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      ThriftButton(
                        label: 'Update password',
                        isLoading: controller.isUpdatingPassword,
                        onPressed: _updatePassword,
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileAvatarPreview extends StatelessWidget {
  const _ProfileAvatarPreview({
    required this.controller,
    required this.previewPath,
  });

  final AdminProfileController controller;
  final String? previewPath;

  @override
  Widget build(BuildContext context) {
    final bytes = controller.pendingAvatarBytes;
    if (bytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: Image.memory(bytes, width: 72, height: 72, fit: BoxFit.cover),
      );
    }
    if (previewPath != null && !kIsWeb) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: Image.file(
          File(previewPath!),
          width: 72,
          height: 72,
          fit: BoxFit.cover,
        ),
      );
    }
    return ThriftAvatar(
      imageUrl: controller.avatarUrl,
      name: controller.name,
      size: 72,
    );
  }
}
