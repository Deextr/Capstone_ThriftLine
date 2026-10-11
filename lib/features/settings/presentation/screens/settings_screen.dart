import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../providers/settings_provider.dart';
import '../../../auth/domain/account_mode.dart';
import '../../../../widgets/thrift_widgets.dart'
    show ThriftButton, ThriftButtonVariant, showThriftSnackBar;
import '../../../auth/domain/legal_documents.dart';
import '../../../auth/presentation/widgets/auth_widgets.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    this.showBackButton = true,
    this.showLogout = false,
  });

  final bool showBackButton;
  final bool showLogout;

  @override
  Widget build(BuildContext context) {
    final settingsProvider = context.watch<SettingsProvider>();
    final auth = context.watch<AuthProvider>();
    final mode = auth.isSeller ? AccountMode.seller : AccountMode.buyer;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Settings'),
        automaticallyImplyLeading: showBackButton,
        leading: showBackButton
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.pop(),
              )
            : null,
      ),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            AppConstants.spacingMd,
            AppConstants.spacingSm,
            AppConstants.spacingMd,
            showBackButton ? AppConstants.spacingSm : 112,
          ),
          children: [
            _buildSection(
              title: 'Preferences',
              children: [
                SwitchListTile(
                  title: Text('Push Notifications', style: AppTypography.body),
                  subtitle: Text(
                    auth.isSeller
                        ? 'Seller workspace alerts'
                        : 'Buyer workspace alerts',
                    style: AppTypography.caption,
                  ),
                  value: settingsProvider.pushFor(mode),
                  activeThumbColor: AppColors.primary,
                  onChanged: settingsProvider.isSavingPush
                      ? null
                      : (value) async {
                          final ok = await settingsProvider
                              .setPushNotifications(value, mode: mode);
                          if (!context.mounted) return;
                          if (!ok) {
                            showThriftSnackBar(
                              context,
                              'Could not save push notification preference.',
                              isError: true,
                            );
                          }
                        },
                ),
                SwitchListTile(
                  title: Text('Email Notifications', style: AppTypography.body),
                  subtitle: Text(
                    'Optional updates only — security emails still send',
                    style: AppTypography.caption,
                  ),
                  value: settingsProvider.emailFor(mode),
                  activeThumbColor: AppColors.primary,
                  onChanged: settingsProvider.isSavingEmail
                      ? null
                      : (value) async {
                          final ok = await settingsProvider
                              .setEmailNotifications(value, mode: mode);
                          if (!context.mounted) return;
                          if (!ok) {
                            showThriftSnackBar(
                              context,
                              'Could not save email notification preference.',
                              isError: true,
                            );
                          }
                        },
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildSection(
              title: 'Support',
              children: [
                ListTile(
                  leading: Icon(
                    Icons.help_outline_rounded,
                    color: AppColors.textPrimary,
                    size: 22,
                  ),
                  title: Text('Help & FAQ', style: AppTypography.body),
                  trailing: Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: AppColors.textHint,
                  ),
                  onTap: () => context.push(
                    RouteNames.legalDocument(LegalDocumentType.faq),
                  ),
                ),
                ListTile(
                  leading: Icon(
                    Icons.description_outlined,
                    color: AppColors.textPrimary,
                    size: 22,
                  ),
                  title: Text(
                    'Terms and Conditions',
                    style: AppTypography.body,
                  ),
                  trailing: Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: AppColors.textHint,
                  ),
                  onTap: () => context.push(
                    RouteNames.legalDocument(LegalDocumentType.terms),
                  ),
                ),
                ListTile(
                  leading: Icon(
                    Icons.privacy_tip_outlined,
                    color: AppColors.textPrimary,
                    size: 22,
                  ),
                  title: Text('Privacy Policy', style: AppTypography.body),
                  trailing: Icon(
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
                  leading: Icon(
                    Icons.info_outline_rounded,
                    color: AppColors.textPrimary,
                    size: 22,
                  ),
                  title: Text('About ThriftLine', style: AppTypography.body),
                  trailing: Icon(
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
            if (showLogout) ...[
              const SizedBox(height: 24),
              ThriftButton(
                label: 'Logout',
                variant: ThriftButtonVariant.ghost,
                color: AppColors.error,
                onPressed: () => confirmAndLogout(context),
              ),
            ],
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
