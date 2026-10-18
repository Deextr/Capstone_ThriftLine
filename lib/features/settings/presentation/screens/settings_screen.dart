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
import '../widgets/push_notification_preferences.dart';

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
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            AppConstants.spacingMd,
            AppConstants.spacingSm,
            AppConstants.spacingMd,
            showBackButton ? AppConstants.spacingSm : 112,
          ),
          children: [
            _buildSection(
              title: 'Notifications',
              children: _withDividers([
                PushNotificationPreferences(mode: mode),
                SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 2,
                  ),
                  title: Text('Email updates', style: AppTypography.body),
                  subtitle: Text(
                    'Optional marketplace updates. Security emails still send.',
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
              ]),
            ),
            const SizedBox(height: 20),
            _buildSection(
              title: 'Help & legal',
              children: _withDividers([
                _SettingsNavTile(
                  icon: Icons.help_outline_rounded,
                  label: 'Help & FAQ',
                  onTap: () => context.push(
                    RouteNames.legalDocument(LegalDocumentType.faq),
                  ),
                ),
                _SettingsNavTile(
                  icon: Icons.description_outlined,
                  label: 'Terms and Conditions',
                  onTap: () => context.push(
                    RouteNames.legalDocument(LegalDocumentType.terms),
                  ),
                ),
                _SettingsNavTile(
                  icon: Icons.privacy_tip_outlined,
                  label: 'Privacy Policy',
                  onTap: () => context.push(
                    RouteNames.legalDocument(LegalDocumentType.privacy),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 20),
            _buildSection(
              title: 'About',
              children: [
                _SettingsNavTile(
                  icon: Icons.info_outline_rounded,
                  label: 'About ThriftLine',
                  subtitle: 'Learn what we do and how we keep buyers safe',
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

  static List<Widget> _withDividers(List<Widget> children) {
    if (children.length <= 1) return children;
    final out = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      out.add(children[i]);
      if (i < children.length - 1) {
        out.add(const Divider(height: 1, indent: 16, endIndent: 16));
      }
    }
    return out;
  }

  Widget _buildSection({
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 8),
          child: Text(
            title,
            style: AppTypography.subheading.copyWith(
              fontSize: 13,
              color: AppColors.textSecondary,
              letterSpacing: 0.2,
            ),
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

class _SettingsNavTile extends StatelessWidget {
  const _SettingsNavTile({
    required this.icon,
    required this.label,
    this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Icon(icon, color: AppColors.textPrimary, size: 22),
      title: Text(label, style: AppTypography.body),
      subtitle: subtitle != null
          ? Text(subtitle!, style: AppTypography.caption)
          : null,
      trailing: Icon(
        Icons.chevron_right_rounded,
        size: 22,
        color: AppColors.textHint,
      ),
      onTap: onTap,
    );
  }
}
