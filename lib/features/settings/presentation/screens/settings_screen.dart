import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../providers/settings_provider.dart';
import '../../../auth/domain/legal_documents.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>().settings;
    final user = context.watch<AuthProvider>().user;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spacingMd,
            vertical: AppConstants.spacingSm,
          ),
          children: [
            _buildSection(
              title: 'Preferences',
              children: [
                SwitchListTile(
                  title: Text('Push Notifications', style: AppTypography.body),
                  value: settings.pushNotificationsEnabled,
                  activeThumbColor: AppColors.primary,
                  onChanged: (value) => context
                      .read<SettingsProvider>()
                      .setPushNotifications(value),
                ),
                SwitchListTile(
                  title: Text('Email Notifications', style: AppTypography.body),
                  value: settings.emailNotificationsEnabled,
                  activeThumbColor: AppColors.primary,
                  onChanged: (value) => context
                      .read<SettingsProvider>()
                      .setEmailNotifications(value),
                ),
                ListTile(
                  title: Text('Language', style: AppTypography.body),
                  subtitle: Text('English', style: AppTypography.caption),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                ),
                ListTile(
                  title: Text('Phone number', style: AppTypography.body),
                  subtitle: Text(
                    user?.isPhoneVerified == true
                        ? (user?.phone ?? 'Verified')
                        : 'Not verified',
                    style: AppTypography.caption,
                  ),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () => context.push(RouteNames.verifyPhone),
                ),
                ListTile(
                  title: Text('Addresses', style: AppTypography.body),
                  subtitle: Text(
                    'Delivery addresses for checkout',
                    style: AppTypography.caption,
                  ),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () => context.push(RouteNames.addresses),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildSection(
              title: 'Support',
              children: [
                ListTile(
                  leading: const Icon(
                    Icons.help_outline_rounded,
                    color: AppColors.textPrimary,
                    size: 22,
                  ),
                  title: Text('Help & FAQ', style: AppTypography.body),
                  trailing: const Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: AppColors.textHint,
                  ),
                  onTap: () => context.push(
                    RouteNames.legalDocument(LegalDocumentType.faq),
                  ),
                ),
                ListTile(
                  leading: const Icon(
                    Icons.description_outlined,
                    color: AppColors.textPrimary,
                    size: 22,
                  ),
                  title: Text('Terms and Conditions', style: AppTypography.body),
                  trailing: const Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: AppColors.textHint,
                  ),
                  onTap: () => context.push(
                    RouteNames.legalDocument(LegalDocumentType.terms),
                  ),
                ),
                ListTile(
                  leading: const Icon(
                    Icons.privacy_tip_outlined,
                    color: AppColors.textPrimary,
                    size: 22,
                  ),
                  title: Text('Privacy Policy', style: AppTypography.body),
                  trailing: const Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: AppColors.textHint,
                  ),
                  onTap: () => context.push(
                    RouteNames.legalDocument(LegalDocumentType.privacy),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildSection(
              title: 'About',
              children: [
                ListTile(
                  leading: const Icon(
                    Icons.info_outline_rounded,
                    color: AppColors.textPrimary,
                    size: 22,
                  ),
                  title: Text('About ThriftLine', style: AppTypography.body),
                  trailing: const Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: AppColors.textHint,
                  ),
                  onTap: () => context.push(
                    RouteNames.legalDocument(LegalDocumentType.about),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title,
            style: AppTypography.subheading.copyWith(fontSize: 14),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Column(children: children),
          ),
        ),
      ],
    );
  }
}
