import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../features/auth/data/auth_service.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../widgets/thrift_widgets.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late TextEditingController _nameCtrl;
  late TextEditingController _locationCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _phoneCtrl;
  bool _emailVerified = false;
  bool _phoneVerified = false;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    final user = AuthService().getUserByUsername(auth.username ?? '');
    _nameCtrl = TextEditingController(text: user?.name ?? '');
    _locationCtrl = TextEditingController(text: user?.location ?? '');
    _emailCtrl = TextEditingController();
    _phoneCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _locationCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  void _showVerificationDialog({
    required String type,
    required String value,
    required VoidCallback onVerified,
  }) {
    final codeCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              type == 'email' ? Icons.email_outlined : Icons.phone_outlined,
              color: AppColors.primary,
              size: 24,
            ),
            const SizedBox(width: 8),
            Text('Verify $type', style: AppTypography.subheading),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'We\'ve sent a verification code to:',
              style: AppTypography.body,
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: AppTypography.body.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 20),
            ThriftTextField(
              label: 'Verification Code',
              hint: 'Enter 6-digit code',
              controller: codeCtrl,
              keyboardType: TextInputType.number,
              icon: Icons.lock_outline,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  showThriftSnackBar(ctx, 'Code resent!');
                },
                child: Text(
                  'Resend code',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: AppTypography.body.copyWith(color: AppColors.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              onVerified();
              showThriftSnackBar(
                context,
                '${type[0].toUpperCase()}${type.substring(1)} verified successfully!',
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Verify', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Edit Profile'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
          elevation: 0,
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacingMd, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Stack(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.primaryLight, width: 3),
                        ),
                        child: const CircleAvatar(
                          radius: 45,
                          backgroundColor: AppColors.surfaceVariant,
                          child: Icon(Icons.person_outline, size: 45, color: AppColors.textSecondary),
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: GestureDetector(
                          onTap: () => showThriftSnackBar(context, 'Change photo coming soon'),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                              border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 3),
                            ),
                            child: const Icon(Icons.camera_alt_outlined, size: 18, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                Text('Personal Information', style: AppTypography.subheading),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2))
                    ]
                  ),
                  child: Column(
                    children: [
                      ThriftTextField(label: 'Full Name', controller: _nameCtrl, icon: Icons.person_outline),
                      const SizedBox(height: 16),
                      ThriftTextField(label: 'Location', controller: _locationCtrl, icon: Icons.location_on_outlined),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                Text('Contact Details', style: AppTypography.subheading),
                const SizedBox(height: 16),
                // Email Verification
                _verificationTile(
                  icon: Icons.email_outlined,
                  title: 'Email',
                  value: _emailCtrl.text.isEmpty ? 'Not set' : _emailCtrl.text,
                  isVerified: _emailVerified,
                  onVerify: () {
                    if (_emailCtrl.text.isEmpty) {
                      _showEditFieldDialog(
                        'Email',
                        _emailCtrl,
                        TextInputType.emailAddress,
                        () {
                          setState(() {});
                          _showVerificationDialog(
                            type: 'email',
                            value: _emailCtrl.text,
                            onVerified: () => setState(() => _emailVerified = true),
                          );
                        },
                      );
                    } else {
                      _showVerificationDialog(
                        type: 'email',
                        value: _emailCtrl.text,
                        onVerified: () => setState(() => _emailVerified = true),
                      );
                    }
                  },
                ),
                const SizedBox(height: 12),
                // Phone Verification
                _verificationTile(
                  icon: Icons.phone_outlined,
                  title: 'Phone Number',
                  value: _phoneCtrl.text.isEmpty ? 'Not set' : _phoneCtrl.text,
                  isVerified: _phoneVerified,
                  onVerify: () {
                    if (_phoneCtrl.text.isEmpty) {
                      _showEditFieldDialog(
                        'Phone Number',
                        _phoneCtrl,
                        TextInputType.phone,
                        () {
                          setState(() {});
                          _showVerificationDialog(
                            type: 'phone',
                            value: _phoneCtrl.text,
                            onVerified: () => setState(() => _phoneVerified = true),
                          );
                        },
                      );
                    } else {
                      _showVerificationDialog(
                        type: 'phone',
                        value: _phoneCtrl.text,
                        onVerified: () => setState(() => _phoneVerified = true),
                      );
                    }
                  },
                ),
                const SizedBox(height: 48),
                ThriftButton(
                  label: 'Save Changes',
                  onPressed: () {
                    showThriftSnackBar(context, 'Profile updated!');
                    context.pop();
                  },
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _verificationTile({
    required IconData icon,
    required String title,
    required String value,
    required bool isVerified,
    required VoidCallback onVerify,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isVerified ? AppColors.success.withValues(alpha: 0.3) : AppColors.border.withValues(alpha: 0.5),
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2))
        ]
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isVerified ? AppColors.success.withValues(alpha: 0.1) : AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: isVerified ? AppColors.success : AppColors.textHint,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTypography.body.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (isVerified)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle, size: 14, color: AppColors.success),
                  const SizedBox(width: 4),
                  Text(
                    'Verified',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.success,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            )
          else
            TextButton(
              onPressed: onVerify,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                backgroundColor: AppColors.primaryLight,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              child: Text(
                'Verify',
                style: AppTypography.body.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showEditFieldDialog(
    String label,
    TextEditingController controller,
    TextInputType keyboardType,
    VoidCallback onDone,
  ) {
    final tempCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Add $label', style: AppTypography.subheading),
        content: ThriftTextField(
          label: label,
          hint: label == 'Email' ? 'your@email.com' : '+63 9XX XXX XXXX',
          controller: tempCtrl,
          keyboardType: keyboardType,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: AppTypography.body.copyWith(color: AppColors.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              controller.text = tempCtrl.text;
              Navigator.pop(ctx);
              onDone();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Continue', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
