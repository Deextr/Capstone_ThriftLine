import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../widgets/thrift_widgets.dart';

class AdminWebSettingsPage extends StatelessWidget {
  const AdminWebSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    return ColoredBox(
      color: AppColors.background,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Administrator profile',
            style: AppTypography.subheading.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(user?.email ?? '', style: AppTypography.body),
          Text(user?.name ?? '', style: AppTypography.caption),
          const SizedBox(height: 32),
          ListTile(
            title: const Text('Bid risk events'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(RouteNames.adminBidRiskEvents),
          ),
          const Divider(),
          const SizedBox(height: 24),
          ThriftButton(
            label: 'Sign out',
            onPressed: () async {
              await context.read<AuthProvider>().logout();
              if (context.mounted) context.go(RouteNames.adminLogin);
            },
          ),
        ],
      ),
    );
  }
}
