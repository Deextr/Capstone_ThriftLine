import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../features/auth/data/auth_service.dart';
import '../../../../models/enums.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../providers/data_provider.dart';
import '../../../../widgets/thrift_widgets.dart';

class BuyerProfileTab extends StatelessWidget {
  const BuyerProfileTab({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final data = context.watch<DataProvider>();
    final user = AuthService().getUserByUsername(auth.username ?? '');
    final buyerId = auth.user?.id ?? 'buyer_maya';
    final activeBids = data.bidsForBuyer(buyerId, BidTab.active).length;
    final purchases = data.ordersForBuyer(buyerId).length;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(AppConstants.spacingMd),
        children: [
          Center(
            child: Column(
              children: [
                ThriftAvatar(imageUrl: user?.avatarUrl ?? '', size: 80),
                const SizedBox(height: 12),
                Text(user?.name ?? '', style: AppTypography.heading),
                Text('@${user?.username ?? ''}', style: AppTypography.caption),
                const SizedBox(height: 8),
                const ThriftBadge(label: 'Buyer', variant: BadgeVariant.primary),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.location_on, size: 14, color: AppColors.primary),
                    Text(user?.location ?? '', style: AppTypography.caption),
                  ],
                ),
                const SizedBox(height: 16),
                ThriftButton(
                  label: 'Edit Profile',
                  variant: ThriftButtonVariant.outline,
                  expand: false,
                  onPressed: () => context.push(RouteNames.editProfile),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _stat('Purchases', '$purchases'),
              _stat('Active Bids', '$activeBids'),
              _stat('Saved Items', '${data.savedCount}'),
            ],
          ),
          const SizedBox(height: 24),
          _section('My Activity', [
            _menuItem(context, 'Purchase History', () => context.push(RouteNames.purchaseHistory)),
            _menuItem(context, 'Active Bids', () {}),
            _menuItem(context, 'Saved Items', () => context.push(RouteNames.savedItems)),
            _menuItem(context, 'My Requests', () {}),
          ]),
          _section('Account', [
            _menuItem(context, 'Edit Profile', () => context.push(RouteNames.editProfile)),
            SwitchListTile(
              title: Text('Notifications', style: AppTypography.body),
              value: data.notificationsEnabled,
              onChanged: (_) => data.toggleNotifications(),
            ),
            _menuItem(context, 'Payment Methods', () => showThriftSnackBar(context, 'Coming soon')),
            _menuItem(context, 'Addresses', () => showThriftSnackBar(context, 'Coming soon')),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.storefront, color: AppColors.primary, size: 20),
              ),
              title: Text('Become a Seller', style: AppTypography.body.copyWith(fontWeight: FontWeight.w600)),
              subtitle: Text('Start selling your thrift items', style: AppTypography.caption),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: () => context.push(RouteNames.becomeSeller),
            ),
          ]),
          _section('Help & Support', [
            _menuItem(context, 'Help Center', () => showThriftSnackBar(context, 'Help center coming soon')),
            _menuItem(context, 'Report a Problem', () => showThriftSnackBar(context, 'Report submitted')),
            _menuItem(context, 'About Thriftline', () => showThriftSnackBar(context, 'Thriftline v1.0.0')),
          ]),
          const SizedBox(height: 16),
          ThriftButton(
            label: 'Logout',
            variant: ThriftButtonVariant.ghost,
            color: AppColors.error,
            onPressed: () async {
              await auth.logout();
              if (context.mounted) context.go(RouteNames.login);
            },
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value) => Column(
        children: [
          Text(value, style: AppTypography.heading.copyWith(color: AppColors.primary)),
          Text(label, style: AppTypography.caption),
        ],
      );

  Widget _section(String title, List<Widget> children) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(title, style: AppTypography.subheading),
          ),
          ThriftCard(
            padding: EdgeInsets.zero,
            child: Column(children: children),
          ),
          const SizedBox(height: 16),
        ],
      );

  Widget _menuItem(BuildContext context, String title, VoidCallback onTap) => ListTile(
        title: Text(title, style: AppTypography.body),
        trailing: const Icon(Icons.chevron_right, size: 20),
        onTap: onTap,
      );
}
