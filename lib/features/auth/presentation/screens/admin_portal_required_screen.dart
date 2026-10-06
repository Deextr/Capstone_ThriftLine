import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../widgets/thrift_widgets.dart';

/// Shown on the mobile app when an administrator account is signed in.
class AdminPortalRequiredScreen extends StatelessWidget {
  const AdminPortalRequiredScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(flex: 2),
              Icon(Icons.admin_panel_settings_outlined,
                  size: 56, color: AppColors.primary),
              const SizedBox(height: 24),
              Text(
                'ThriftLine Admin',
                style: AppTypography.heading.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'This administrator account is intended for the ThriftLine Admin Portal on the web.',
                style: AppTypography.body.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.45,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Use a buyer or seller account in this app, or open the admin portal in your browser.',
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const Spacer(flex: 3),
              ThriftButton(
                label: 'Sign out',
                onPressed: () async {
                  await context.read<AuthProvider>().logout();
                },
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
