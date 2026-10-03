import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/routes/route_names.dart';
import '../../../providers/auth_provider.dart';
import '../../auth/domain/auth_user.dart';
import '../../../providers/settings_provider.dart';
import '../../auth/domain/account_mode.dart';
import '../../../widgets/thrift_widgets.dart';
import '../../auth/presentation/widgets/auth_widgets.dart';
import '../../buyer/controllers/buyer_orders_controller.dart';
import '../../buyer/data/buyer_purchase_category.dart';
import '../../../models/review_model.dart';
import '../../../providers/following_shops_provider.dart';
import '../../trust_safety/data/buyer_to_rate_buckets.dart';
import '../presentation/widgets/following_shops_preview.dart';
import '../presentation/widgets/switch_account_sheet.dart';
import '../presentation/widgets/switchable_avatar.dart';

class BuyerProfileTab extends StatelessWidget {
  const BuyerProfileTab({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final settings = context.watch<SettingsProvider>();
    final buyerOrders = context.watch<BuyerOrdersController>();
    final followingProvider = context.watch<FollowingShopsProvider>();
    final user = auth.user;

    final myPurchasesCount = buyerOrders.orders
        .where(orderIncludedInMyPurchases)
        .length;
    final myReviews = <String, ReviewModel>{
      for (final order in buyerOrders.orders)
        if (buyerOrders.reviewFor(order.id) != null)
          order.id: buyerOrders.reviewFor(order.id)!,
    };
    final toRateCount = ordersPendingBuyerReview(
      buyerOrders.orders,
      myReviews,
    ).length;
    final followingCount = followingProvider.followingCount;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppConstants.spacingMd),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.spacingMd,
            ),
            child: _ProfileHeader(auth: auth),
          ),
          const SizedBox(height: 28),
          _SectionCard(
            title: 'My Activity',
            children: [
              _MenuItem(
                icon: Icons.shopping_bag_outlined,
                label: myPurchasesCount > 0
                    ? 'My Purchases ($myPurchasesCount)'
                    : 'My Purchases',
                onTap: () => context.push(RouteNames.myPurchases),
              ),
              _MenuItem(
                icon: Icons.star_outline_rounded,
                label: toRateCount > 0 ? 'To Rate ($toRateCount)' : 'To Rate',
                onTap: () async {
                  await context.push(RouteNames.buyerToRate);
                  if (!context.mounted) return;
                  await context.read<BuyerOrdersController>().load(
                    showSpinner: false,
                  );
                },
              ),
              _MenuItem(
                icon: Icons.favorite_border,
                label: 'Saved Items',
                onTap: () => context.push(RouteNames.savedItems),
              ),
              _MenuItem(
                icon: Icons.storefront_outlined,
                label: followingCount > 0
                    ? 'Following Shops ($followingCount)'
                    : 'Following Shops',
                onTap: () => context.push(RouteNames.followingShops),
              ),
            ],
          ),
          FollowingShopsPreview(
            followedShops: followingProvider.followedShops,
            isLoading: followingProvider.isLoading,
            onViewAll: () => context.push(RouteNames.followingShops),
          ),
          _SectionCard(
            title: 'Account & Settings',
            children: [
              _MenuItem(
                icon: Icons.person_outline_rounded,
                label: 'Edit Profile',
                onTap: () => context.push(RouteNames.editProfile),
              ),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                leading: const Icon(
                  Icons.notifications_none_outlined,
                  color: AppColors.textPrimary,
                  size: 22,
                ),
                title: Text('Notifications', style: AppTypography.body),
                trailing: Switch(
                  value: settings.pushFor(AccountMode.buyer),
                  onChanged: settings.isSavingPush
                      ? null
                      : (value) => settings.setPushNotifications(
                            value,
                            mode: AccountMode.buyer,
                          ),
                  activeTrackColor: AppColors.primary.withValues(alpha: 0.4),
                  activeThumbColor: AppColors.primary,
                ),
              ),
              _MenuItem(
                icon: Icons.payment_outlined,
                label: 'Payment Methods',
                onTap: () => showThriftSnackBar(context, 'Coming soon'),
              ),
              _MenuItem(
                icon: Icons.location_on_outlined,
                label: 'Addresses',
                onTap: () => context.push(RouteNames.addresses),
              ),
              _MenuItem(
                icon: Icons.settings_outlined,
                label: 'Settings',
                onTap: () => context.push(RouteNames.settings),
              ),
              const Divider(height: 1, thickness: 1, color: AppColors.border),
              if (auth.canSwitchAccounts)
                _MenuItem(
                  icon: Icons.sync_alt_rounded,
                  label: 'Switch Account',
                  onTap: () => SwitchAccountSheet.show(context),
                )
              else
                _BecomeSellerTile(user: user),
            ],
          ),
          _SectionCard(
            title: 'Trust & Safety',
            children: [
              _TrustMenuItem(
                icon: Icons.flag_outlined,
                iconColor: AppColors.error,
                iconBackground: AppColors.error.withValues(alpha: 0.1),
                title: 'Report a Seller',
                subtitle: 'Report suspicious or fraudulent activity',
                onTap: () => context.push(RouteNames.reportSeller),
              ),
              _TrustMenuItem(
                icon: Icons.assignment_outlined,
                iconColor: AppColors.primary,
                iconBackground: AppColors.primary.withValues(alpha: 0.1),
                title: 'My Reports',
                subtitle: 'Track reports you submitted',
                onTap: () => context.push(RouteNames.myReports),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.spacingMd,
            ),
            child: ThriftButton(
              label: 'Logout',
              variant: ThriftButtonVariant.ghost,
              color: AppColors.error,
              onPressed: () => confirmAndLogout(context),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.auth});

  final AuthProvider auth;

  @override
  Widget build(BuildContext context) {
    final user = auth.user;
    final name = auth.displayName ?? user?.name ?? '';
    final username = user?.username ?? '';
    final email = user?.email ?? '';
    final phone = user?.phone ?? '';

    return Column(
      children: [
        SwitchableAvatar(
          key: ValueKey('buyer-profile-${auth.activeAvatarUrl}'),
          imageUrl: auth.activeAvatarUrl,
          name: name,
          canSwitch: auth.canSwitchAccounts,
          onSwitch: () => SwitchAccountSheet.show(context),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                name.isNotEmpty ? name : 'No Name',
                style: AppTypography.heading.copyWith(fontSize: 22),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
            if (user?.isVerified == true) ...[
              const SizedBox(width: 6),
              const Icon(Icons.verified, color: AppColors.primary, size: 20),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text(
          username.isNotEmpty ? '@$username' : '@username',
          style: AppTypography.caption.copyWith(fontSize: 14),
        ),
        if (email.isNotEmpty || phone.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              if (email.isNotEmpty)
                _ContactChip(icon: Icons.email_outlined, label: email),
              if (phone.isNotEmpty)
                _ContactChip(icon: Icons.phone_outlined, label: phone),
            ],
          ),
        ],
      ],
    );
  }
}

class _ContactChip extends StatelessWidget {
  const _ContactChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.textSecondary),
        const SizedBox(width: 4),
        Text(
          label,
          style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacingMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: Text(
              title,
              style: AppTypography.subheading.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Material(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.border.withValues(alpha: 0.5),
                ),
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
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Icon(icon, color: AppColors.textPrimary, size: 22),
      title: Text(label, style: AppTypography.body),
      trailing: const Icon(
        Icons.chevron_right,
        size: 20,
        color: AppColors.textHint,
      ),
      onTap: onTap,
    );
  }
}

class _TrustMenuItem extends StatelessWidget {
  const _TrustMenuItem({
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: iconBackground,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: iconColor, size: 22),
      ),
      title: Text(
        title,
        style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(subtitle, style: AppTypography.caption),
      trailing: const Icon(
        Icons.chevron_right,
        size: 20,
        color: AppColors.textHint,
      ),
      onTap: onTap,
    );
  }
}

class _BecomeSellerTile extends StatelessWidget {
  const _BecomeSellerTile({required this.user});

  final AuthUser? user;

  @override
  Widget build(BuildContext context) {
    final status = user?.verificationStatus ?? 'none';

    IconData icon = Icons.storefront_outlined;
    Color iconColor = AppColors.primary;
    Color bgColor = AppColors.primaryLight;
    String title = 'Become a Seller';
    String subtitle = 'Start selling your thrift items';
    Widget? trailing = const Icon(
      Icons.chevron_right,
      size: 20,
      color: AppColors.textHint,
    );

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
          style: AppTypography.caption.copyWith(
            color: AppColors.warning,
            fontWeight: FontWeight.bold,
          ),
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
          style: AppTypography.caption.copyWith(
            color: AppColors.error,
            fontWeight: FontWeight.bold,
          ),
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
      title: Text(
        title,
        style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(subtitle, style: AppTypography.caption),
      trailing: trailing,
      onTap: () => context.push(RouteNames.becomeSeller),
    );
  }
}
