import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import '../../../widgets/thrift_widgets.dart';
import 'edit_profile_email_section.dart';

class EditProfileForm extends StatefulWidget {
  const EditProfileForm({
    super.key,
    required this.initialName,
    required this.initialUsername,
    required this.initialEmail,
    required this.initialPhone,
    required this.isSaving,
    required this.onSave,
    required this.isSellerMode,
    required this.canChangeEmail,
    this.errorMessage,
  });

  final String initialName;
  final String initialUsername;
  final String initialEmail;
  final String initialPhone;
  final bool isSaving;
  final bool isSellerMode;
  final bool canChangeEmail;
  final String? errorMessage;
  final Future<void> Function({
    required String fullName,
    required String username,
    required String phone,
  }) onSave;

  @override
  State<EditProfileForm> createState() => _EditProfileFormState();
}

class _EditProfileFormState extends State<EditProfileForm> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameController;
  late TextEditingController _usernameController;
  late TextEditingController _phoneController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _usernameController = TextEditingController(text: widget.initialUsername);
    _phoneController = TextEditingController(text: widget.initialPhone);
  }

  @override
  void didUpdateWidget(EditProfileForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialName != widget.initialName &&
        _nameController.text.isEmpty) {
      _nameController.text = widget.initialName;
    }
    if (oldWidget.initialUsername != widget.initialUsername &&
        _usernameController.text.isEmpty) {
      _usernameController.text = widget.initialUsername;
    }
    if (oldWidget.initialPhone != widget.initialPhone &&
        _phoneController.text.isEmpty) {
      _phoneController.text = widget.initialPhone;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      widget.onSave(
        fullName: _nameController.text,
        username: _usernameController.text,
        phone: _phoneController.text,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.errorMessage != null && widget.errorMessage!.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: AppColors.error, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.errorMessage!,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                )
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ThriftTextField(
                  label: widget.isSellerMode ? 'Shop name' : 'Full name',
                  hint: widget.isSellerMode
                      ? 'Your shop display name'
                      : 'Enter your full name',
                  controller: _nameController,
                  icon: widget.isSellerMode
                      ? Icons.store_outlined
                      : Icons.person_outline,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return widget.isSellerMode
                          ? 'Shop name is required'
                          : 'Full name is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                ThriftTextField(
                  label: 'Username',
                  hint: 'john123',
                  controller: _usernameController,
                  icon: Icons.alternate_email,
                  validator: (value) {
                    final trimmed = value?.trim() ?? '';
                    if (trimmed.isEmpty) return 'Username is required';
                    final regex = RegExp(r'^[a-zA-Z0-9]+$');
                    if (!regex.hasMatch(trimmed)) {
                      return 'Letters and numbers only. No spaces or special characters.';
                    }
                    return null;
                  },
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 4),
                  child: Text(
                    'Shared across Buyer and Seller modes.',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textHint,
                      fontSize: 11,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                EditProfileEmailSection(
                  currentEmail: widget.initialEmail,
                  canChangeEmail: widget.canChangeEmail,
                ),
                const SizedBox(height: 16),
                ThriftTextField(
                  label: 'Phone number',
                  labelSuffix: const ThriftBadge(
                    label: 'Unverified',
                    variant: BadgeVariant.warning,
                  ),
                  hint: '+63 9XX XXX XXXX',
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d\+\-\s\(\)]')),
                  ],
                  icon: Icons.phone_outlined,
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          ThriftButton(
            label: widget.isSaving ? 'Saving...' : 'Save changes',
            isLoading: widget.isSaving,
            onPressed: widget.isSaving ? null : _submit,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
