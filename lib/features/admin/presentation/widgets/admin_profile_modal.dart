import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/utils/validators.dart';
import '../../../../features/auth/data/auth_service.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../controllers/admin_profile_controller.dart';

Future<void> showAdminProfileModal(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) {
      return ChangeNotifierProvider(
        create: (context) => AdminProfileController(
          supabase: context.read<SupabaseService>(),
          auth: context.read<AuthProvider>(),
          authService: context.read<AuthService>(),
        ),
        child: const AdminProfileModal(),
      );
    },
  );
}

class AdminProfileModal extends StatefulWidget {
  const AdminProfileModal({super.key});

  @override
  State<AdminProfileModal> createState() => _AdminProfileModalState();
}

class _AdminProfileModalState extends State<AdminProfileModal> {
  final _profileFormKey = GlobalKey<FormState>();
  final _passwordFormKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _showCurrent = false;
  bool _showNew = false;
  bool _showConfirm = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: context.read<AdminProfileController>().name,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (!_profileFormKey.currentState!.validate()) return;
    final controller = context.read<AdminProfileController>();
    controller.setName(_nameController.text);
    await controller.saveProfile();
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
      setState(() {
        _showCurrent = false;
        _showNew = false;
        _showConfirm = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 820;
    final maxWidth = size.width < 960 ? size.width - 32 : 920.0;
    final maxHeight = size.height * 0.9;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      backgroundColor: palette.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        side: BorderSide(color: palette.border),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ModalHeader(onClose: () => Navigator.of(context).pop()),
            Divider(height: 1, color: palette.border),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  wide ? 28 : 20,
                  20,
                  wide ? 28 : 20,
                  24,
                ),
                child: wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 11, child: _accountColumn()),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 22),
                            child: SizedBox(
                              height: 420,
                              child: VerticalDivider(
                                width: 1,
                                color: palette.border,
                              ),
                            ),
                          ),
                          Expanded(flex: 8, child: _pictureColumn()),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _pictureColumn(),
                          const SizedBox(height: 28),
                          Divider(color: palette.border),
                          const SizedBox(height: 20),
                          _accountColumn(),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _accountColumn() {
    final controller = context.watch<AdminProfileController>();
    return Form(
      key: _profileFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Account information',
            style: AppTypography.sectionTitle.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'This is the name other administrators see on activity logs.',
            style: AppTypography.caption,
          ),
          const SizedBox(height: 16),
          ThriftTextField(
            label: 'Full name',
            controller: _nameController,
            inputFormatters: [
              FilteringTextInputFormatter.allow(
                Validators.fullNameInputCharacters,
              ),
              LengthLimitingTextInputFormatter(Validators.fullNameMaxLength),
            ],
            validator: Validators.adminFullName,
            onChanged: controller.setName,
          ),
          if (controller.profileError != null) ...[
            const SizedBox(height: 8),
            _InlineStatus(message: controller.profileError!, isError: true),
          ] else if (controller.profileSuccess != null) ...[
            const SizedBox(height: 8),
            _InlineStatus(message: controller.profileSuccess!, isError: false),
          ],
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: ThriftButton(
              label: 'Save profile',
              expand: false,
              isLoading: controller.isSavingProfile,
              onPressed: controller.isSavingProfile ? null : _saveProfile,
            ),
          ),
          const SizedBox(height: 22),
          Divider(color: context.palette.border),
          const SizedBox(height: 18),
          _LockedField(
            label: 'Email address',
            value: controller.email.isEmpty ? 'Unavailable' : controller.email,
            helper: 'Managed by ThriftLine sign-in. It cannot be changed here.',
          ),
          const SizedBox(height: 16),
          _LockedField(
            label: 'Account role',
            value: controller.roleLabel,
            helper:
                'Assigned by a Superadmin. You cannot change your own role.',
          ),
          const SizedBox(height: 22),
          Divider(color: context.palette.border),
          const SizedBox(height: 18),
          Text(
            'Change password',
            style: AppTypography.sectionTitle.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            controller.usesEmailPassword
                ? 'Use at least ${Validators.adminPasswordMinLength} characters. '
                      'A passphrase works well.'
                : 'Password changes apply to email sign-in accounts.',
            style: AppTypography.caption,
          ),
          const SizedBox(height: 16),
          if (!controller.usesEmailPassword)
            Text(
              'This account uses another sign-in method, so the password '
              'cannot be changed here.',
              style: AppTypography.body,
            )
          else
            Form(
              key: _passwordFormKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ThriftTextField(
                    label: 'Current password',
                    controller: _currentPasswordController,
                    obscureText: !_showCurrent,
                    suffix: _VisibilityToggle(
                      visible: _showCurrent,
                      tooltip: _showCurrent
                          ? 'Hide current password'
                          : 'Show current password',
                      onPressed: () =>
                          setState(() => _showCurrent = !_showCurrent),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Enter your current password.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  ThriftTextField(
                    label: 'New password',
                    controller: _newPasswordController,
                    obscureText: !_showNew,
                    suffix: _VisibilityToggle(
                      visible: _showNew,
                      tooltip: _showNew
                          ? 'Hide new password'
                          : 'Show new password',
                      onPressed: () => setState(() => _showNew = !_showNew),
                    ),
                    validator: Validators.adminPassword,
                  ),
                  const SizedBox(height: 14),
                  ThriftTextField(
                    label: 'Confirm new password',
                    controller: _confirmPasswordController,
                    obscureText: !_showConfirm,
                    suffix: _VisibilityToggle(
                      visible: _showConfirm,
                      tooltip: _showConfirm
                          ? 'Hide confirmation'
                          : 'Show confirmation',
                      onPressed: () =>
                          setState(() => _showConfirm = !_showConfirm),
                    ),
                    validator: (value) => Validators.confirmPassword(
                      value,
                      _newPasswordController.text,
                    ),
                  ),
                  if (controller.passwordError != null) ...[
                    const SizedBox(height: 8),
                    _InlineStatus(
                      message: controller.passwordError!,
                      isError: true,
                    ),
                  ] else if (controller.passwordSuccess != null) ...[
                    const SizedBox(height: 8),
                    _InlineStatus(
                      message: controller.passwordSuccess!,
                      isError: false,
                    ),
                  ],
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ThriftButton(
                      label: 'Update password',
                      expand: false,
                      isLoading: controller.isUpdatingPassword,
                      onPressed: controller.isUpdatingPassword
                          ? null
                          : _updatePassword,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _pictureColumn() {
    final controller = context.watch<AdminProfileController>();
    final palette = context.palette;

    return Column(
      children: [
        Text(
          'Profile picture',
          style: AppTypography.sectionTitle.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 16),
        _AvatarStage(controller: controller),
        const SizedBox(height: 16),
        Text(
          controller.name.trim().isEmpty ? 'Administrator' : controller.name,
          style: AppTypography.subheading.copyWith(fontWeight: FontWeight.w700),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Text(
          controller.roleLabel,
          style: AppTypography.caption.copyWith(
            color: AppColors.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (controller.email.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            controller.email,
            style: AppTypography.caption,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            ThriftButton(
              label: controller.hasPendingAvatar
                  ? 'Change picture'
                  : 'Upload picture',
              variant: ThriftButtonVariant.outline,
              expand: false,
              onPressed: controller.isSavingProfile
                  ? null
                  : () async {
                      await controller.pickAvatar();
                    },
            ),
            if (controller.hasAvatar || controller.hasPendingAvatar)
              TextButton(
                onPressed: controller.isSavingProfile
                    ? null
                    : controller.hasPendingAvatar
                    ? controller.discardPendingAvatar
                    : controller.markAvatarForRemoval,
                child: Text(
                  controller.hasPendingAvatar
                      ? 'Discard photo'
                      : 'Remove picture',
                  style: AppTypography.label.copyWith(
                    color: palette.errorForeground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'JPEG, PNG, or WebP. Up to 5 MB.',
          style: AppTypography.caption,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _ModalHeader extends StatelessWidget {
  const _ModalHeader({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 8, 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Account settings',
                  style: AppTypography.subheading.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Manage how you appear in the Admin portal.',
                  style: AppTypography.caption,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: onClose,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

class _LockedField extends StatelessWidget {
  const _LockedField({
    required this.label,
    required this.value,
    required this.helper,
  });

  final String label;
  final String value;
  final String helper;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.label.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        DecoratedBox(
          decoration: BoxDecoration(
            color: palette.background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: palette.border),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(Icons.lock_outline, size: 16, color: palette.textHint),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    value,
                    style: AppTypography.body.copyWith(
                      color: palette.textSecondary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(helper, style: AppTypography.caption),
      ],
    );
  }
}

class _AvatarStage extends StatelessWidget {
  const _AvatarStage({required this.controller});

  final AdminProfileController controller;

  @override
  Widget build(BuildContext context) {
    const size = 148.0;
    final bytes = controller.pendingAvatarBytes;

    Widget image;
    if (bytes != null) {
      image = Image.memory(bytes, width: size, height: size, fit: BoxFit.cover);
    } else if (controller.willRemoveAvatar || !controller.hasAvatar) {
      image = _DefaultAvatar(name: controller.name, size: size);
    } else {
      image = ThriftAvatar(
        imageUrl: controller.avatarUrl,
        name: controller.name,
        size: size,
      );
    }

    return Container(
      width: size + 12,
      height: size + 12,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.45),
          width: 2,
        ),
        color: AppColors.primaryLight.withValues(alpha: 0.35),
      ),
      child: ClipOval(child: image),
    );
  }
}

class _DefaultAvatar extends StatelessWidget {
  const _DefaultAvatar({required this.name, required this.size});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty
        ? 'A'
        : name.trim().substring(0, 1).toUpperCase();
    return ColoredBox(
      color: AppColors.primaryLight,
      child: Center(
        child: Text(
          initial,
          style: AppTypography.heading.copyWith(
            fontSize: size * 0.36,
            color: AppColors.primaryDark,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _VisibilityToggle extends StatelessWidget {
  const _VisibilityToggle({
    required this.visible,
    required this.tooltip,
    required this.onPressed,
  });

  final bool visible;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(
        visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
        size: 20,
        color: context.palette.textSecondary,
      ),
    );
  }
}

class _InlineStatus extends StatelessWidget {
  const _InlineStatus({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = isError ? palette.errorForeground : AppColors.primary;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          isError ? Icons.error_outline : Icons.check_circle_outline,
          size: 16,
          color: color,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            message,
            style: AppTypography.caption.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
