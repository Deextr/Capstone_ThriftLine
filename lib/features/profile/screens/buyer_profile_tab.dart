import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/routes/route_names.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/data_provider.dart';
import '../../../widgets/thrift_widgets.dart';

/// Profile tab for **buyer-only** users.
///
/// Layout:
/// ┌─ Profile Header (Avatar, Name, @Username)
/// ├─ My Activity
/// ├─ Account
/// ├─ Seller (Become a Seller)
/// └─ Logout
class BuyerProfileTab extends StatelessWidget {
  const BuyerProfileTab({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final data = context.watch<DataProvider>();
    final user = auth.user;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppConstants.spacingMd),
        children: [
          // ── Profile Header ─────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacingMd),
            child: _ProfileHeader(user: user),
          ),

          const SizedBox(height: 28),

          // ── My Activity ────────────────────────────────────────────────
          _SectionCard(
            title: 'My Activity',
            children: [
              _MenuItem(
                icon: Icons.receipt_long_outlined,
                label: 'Purchase History',
                onTap: () => context.push(RouteNames.purchaseHistory),
              ),
              _MenuItem(
                icon: Icons.gavel_outlined,
                label: 'Active Bids',
                onTap: () => showThriftSnackBar(context, 'Coming soon'),
              ),
              _MenuItem(
                icon: Icons.favorite_border_rounded,
                label: 'Saved Items',
                onTap: () => context.push(RouteNames.savedItems),
              ),
              _MenuItem(
                icon: Icons.inventory_2_outlined,
                label: 'My Requests',
                onTap: () => showThriftSnackBar(context, 'Coming soon'),
              ),
            ],
          ),

          // ── Account ────────────────────────────────────────────────────
          _SectionCard(
            title: 'Account',
            children: [
              _MenuItem(
                icon: Icons.person_outline_rounded,
                label: 'Edit Profile',
                onTap: () => context.push(RouteNames.editProfile),
              ),
              _NotificationToggle(data: data),
              _MenuItem(
                icon: Icons.payment_outlined,
                label: 'Payment Methods',
                onTap: () => showThriftSnackBar(context, 'Coming soon'),
              ),
              _MenuItem(
                icon: Icons.location_on_outlined,
                label: 'Addresses',
                onTap: () => showThriftSnackBar(context, 'Coming soon'),
              ),
              _MenuItem(
                icon: Icons.settings_outlined,
                label: 'Settings',
                onTap: () => context.push(RouteNames.settings),
              ),
            ],
          ),

          // ── Seller ─────────────────────────────────────────────────────
          _SectionCard(
            title: 'Seller',
            children: [
              _BecomeSellerTile(user: user),
            ],
          ),

          // ── Logout ─────────────────────────────────────────────────────
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
}

// =============================================================================
// Profile Header
// =============================================================================

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.user});
  final dynamic user;

  @override
  Widget build(BuildContext context) {
    final name = user?.name ?? '';
    final username = user?.username ?? '';

    return Column(
      children: [
        ThriftAvatar(imageUrl: user?.avatarUrl ?? '', name: name, size: 90),
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
      ],
    );
  }
}

// =============================================================================
// Section Card (reusable section wrapper)
// =============================================================================

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
              style: AppTypography.subheading.copyWith(color: AppColors.textSecondary),
            ),
          ),
          Material(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              decoration: BoxDecoration(
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
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// =============================================================================
// Menu Item
// =============================================================================

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
      trailing: const Icon(Icons.chevron_right, size: 20, color: AppColors.textHint),
      onTap: onTap,
    );
  }
}

// =============================================================================
// Notification Toggle
// =============================================================================

class _NotificationToggle extends StatelessWidget {
  const _NotificationToggle({required this.data});
  final DataProvider data;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: const Icon(Icons.notifications_none_outlined, color: AppColors.textPrimary, size: 22),
      title: Text('Notifications', style: AppTypography.body),
      trailing: Switch(
        value: data.notificationsEnabled,
        onChanged: (_) => data.toggleNotifications(),
        activeTrackColor: AppColors.primary.withValues(alpha: 0.4),
        activeThumbColor: AppColors.primary,
      ),
    );
  }
}

// =============================================================================
// Become a Seller Tile (status-aware)
// =============================================================================

class _BecomeSellerTile extends StatelessWidget {
  const _BecomeSellerTile({required this.user});
  final dynamic user;

  @override
  Widget build(BuildContext context) {
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
      title: Text(title, style: AppTypography.body.copyWith(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: AppTypography.caption),
      trailing: trailing,
      onTap: () => context.push(RouteNames.becomeSeller),
    );
  }
}
