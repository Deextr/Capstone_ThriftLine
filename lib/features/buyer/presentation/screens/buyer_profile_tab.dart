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
        padding: const EdgeInsets.symmetric(vertical: AppConstants.spacingMd),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacingMd),
            child: _buildProfileHeader(context, user),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacingMd),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(child: _stat('Purchases', '$purchases', Icons.shopping_bag_outlined)),
                Container(height: 24, width: 1, color: AppColors.border),
                Expanded(child: _stat('Active Bids', '$activeBids', Icons.gavel_outlined)),
                Container(height: 24, width: 1, color: AppColors.border),
                Expanded(child: _stat('Saved Items', '${data.savedCount}', Icons.favorite_border)),
              ],
            ),
          ),
          const SizedBox(height: 32),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacingMd),
            child: _section('My Activity', [
              _menuItem(context, 'Purchase History', Icons.history_outlined, () => context.push(RouteNames.purchaseHistory)),
              _menuItem(context, 'Active Bids', Icons.gavel_outlined, () {}),
              _menuItem(context, 'Saved Items', Icons.favorite_border, () => context.push(RouteNames.savedItems)),
              _menuItem(context, 'My Requests', Icons.inventory_2_outlined, () {}),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacingMd),
            child: _section('Account', [
              _menuItem(context, 'Edit Profile', Icons.person_outline, () => context.push(RouteNames.editProfile)),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: const Icon(Icons.notifications_none_outlined, color: AppColors.textPrimary, size: 22),
                title: Text('Notifications', style: AppTypography.body),
                trailing: Switch(
                  value: data.notificationsEnabled,
                  onChanged: (_) => data.toggleNotifications(),
                  activeColor: AppColors.primary,
                ),
              ),
              _menuItem(context, 'Payment Methods', Icons.payment_outlined, () => showThriftSnackBar(context, 'Coming soon')),
              _menuItem(context, 'Addresses', Icons.location_on_outlined, () => showThriftSnackBar(context, 'Coming soon')),
              const Divider(height: 1, thickness: 1, color: AppColors.border),
              _buildBecomeSellerTile(context, user),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacingMd),
            child: _section('Trust & Safety', [
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.flag_outlined, color: AppColors.error, size: 22),
                ),
                title: Text('Report a Seller', style: AppTypography.body.copyWith(fontWeight: FontWeight.w600)),
                subtitle: Text('Report suspicious or fraudulent activity', style: AppTypography.caption),
                trailing: const Icon(Icons.chevron_right, size: 20, color: AppColors.textHint),
                onTap: () => context.push(RouteNames.reportSeller),
              ),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.assignment_outlined, color: AppColors.primary, size: 22),
                ),
                title: Text('My Reports', style: AppTypography.body.copyWith(fontWeight: FontWeight.w600)),
                subtitle: Text('Track complaints & appeal decisions', style: AppTypography.caption),
                trailing: const Icon(Icons.chevron_right, size: 20, color: AppColors.textHint),
                onTap: () => context.push(RouteNames.myReports),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacingMd),
            child: _section('Help & Support', [
              _menuItem(context, 'Help Center', Icons.help_outline, () => showThriftSnackBar(context, 'Help center coming soon')),
              _menuItem(context, 'About Thriftline', Icons.info_outline, () => showThriftSnackBar(context, 'Thriftline v1.0.0')),
            ]),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacingMd),
            child: ThriftButton(
              label: 'Logout',
              variant: ThriftButtonVariant.ghost,
              color: AppColors.error,
              onPressed: () async {
                await auth.logout();
                if (context.mounted) context.go(RouteNames.login);
              },
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildBecomeSellerTile(BuildContext context, user) {
    final status = user?.verificationStatus ?? 'none';
    
    IconData icon = Icons.storefront_outlined;
    Color iconColor = AppColors.primary;
    Color bgColor = AppColors.primaryLight;
    String title = 'Become a Seller';
    String subtitle = 'Start selling your thrift items';
    Widget? trailing = const Icon(Icons.chevron_right, size: 20, color: AppColors.textHint);

    if (status == 'pending') {
      icon = Icons.hourglass_empty;
      iconColor = AppColors.warning;
      bgColor = AppColors.warning.withValues(alpha: 0.15);
      title = 'Seller Application';
      subtitle = 'Status: Pending Review';
      trailing = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          'Pending',
          style: AppTypography.caption.copyWith(color: AppColors.warning, fontWeight: FontWeight.bold),
        ),
      );
    } else if (status == 'rejected') {
      icon = Icons.cancel_outlined;
      iconColor = AppColors.error;
      bgColor = AppColors.error.withValues(alpha: 0.15);
      title = 'Seller Application';
      subtitle = 'Status: Rejected (Tap to view)';
      trailing = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          'Rejected',
          style: AppTypography.caption.copyWith(color: AppColors.error, fontWeight: FontWeight.bold),
        ),
      );
    }

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: iconColor, size: 22),
      ),
      title: Text(title, style: AppTypography.body.copyWith(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: AppTypography.caption),
      trailing: trailing,
      onTap: () => context.push(RouteNames.becomeSeller),
    );
  }

  Widget _buildProfileHeader(BuildContext context, user) {
    return Column(
      children: [
        ThriftAvatar(imageUrl: user?.avatarUrl ?? '', size: 90),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(user?.name ?? '', style: AppTypography.heading.copyWith(fontSize: 22)),
            if (user?.isVerified == true) ...[
              const SizedBox(width: 6),
              const Icon(Icons.verified, color: AppColors.primary, size: 20),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text('@${user?.username ?? ''}', style: AppTypography.caption.copyWith(fontSize: 14)),
      ],
    );
  }

  Widget _stat(String label, String value, IconData icon) => Column(
        children: [
          Text(value, style: AppTypography.heading.copyWith(fontSize: 20, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text(label, style: AppTypography.caption),
        ],
      );

  Widget _section(String title, List<Widget> children) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: Text(title, style: AppTypography.subheading.copyWith(color: AppColors.textSecondary)),
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
                )
              ]
            ),
            child: Column(children: children),
          ),
          const SizedBox(height: 24),
        ],
      );

  Widget _menuItem(BuildContext context, String title, IconData icon, VoidCallback onTap) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Icon(icon, color: AppColors.textPrimary, size: 22),
        title: Text(title, style: AppTypography.body),
        trailing: const Icon(Icons.chevron_right, size: 20, color: AppColors.textHint),
        onTap: onTap,
      );
}
