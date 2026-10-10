import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../widgets/thrift_widgets.dart';

class AdminAccessDeniedScreen extends StatelessWidget {
  const AdminAccessDeniedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final reason = GoRouterState.of(context).uri.queryParameters['reason'];
    final deactivated =
        reason == 'deactivated' ||
        context.watch<AuthProvider>().isDeactivatedAdministrator;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 48,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(height: 20),
                Text(
                  deactivated ? 'Account deactivated' : 'Access denied',
                  style: AppTypography.heading.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 12),
                Text(
                  deactivated
                      ? 'This administrator account is deactivated. Ask a Super Admin to restore access.'
                      : 'This portal is for ThriftLine administrators only. Buyer and seller accounts cannot access the admin workspace.',
                  style: AppTypography.body.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.45,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),
                ThriftButton(
                  label: 'Return to sign in',
                  onPressed: () async {
                    await context.read<AuthProvider>().logout();
                    if (context.mounted) context.go(RouteNames.adminLogin);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
