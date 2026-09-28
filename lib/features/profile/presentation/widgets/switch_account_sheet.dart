import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../features/auth/domain/account_mode.dart';
import '../../../../features/auth/domain/auth_user.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../widgets/thrift_widgets.dart';

/// Messenger-style picker for the Buyer and Seller workspaces.
class SwitchAccountSheet extends StatelessWidget {
  const SwitchAccountSheet({super.key});

  static Future<void> show(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    if (!auth.canSwitchAccounts) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const SwitchAccountSheet(),
    );
  }

  Future<void> _select(BuildContext context, AccountMode mode) async {
    final auth = context.read<AuthProvider>();
    if (auth.activeAccount == mode) {
      Navigator.of(context).pop();
      return;
    }
    final router = GoRouter.of(context);
    await auth.switchActiveAccount(mode);
    if (!context.mounted) return;
    Navigator.of(context).pop();
    router.go(auth.homeRoute);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppConstants.spacingMd,
          AppConstants.spacingSm,
          AppConstants.spacingMd,
          AppConstants.spacingLg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Switch account', style: AppTypography.heading),
            const SizedBox(height: 4),
            Text(
              'Use your Buyer and Seller accounts without signing in again.',
              style: AppTypography.caption,
            ),
            const SizedBox(height: 16),
            _AccountTile(
              mode: AccountMode.buyer,
              title: user?.name.isNotEmpty == true
                  ? user!.name
                  : 'Buyer account',
              subtitle: 'Buyer account',
              imageUrl: user?.avatarUrl ?? '',
              selected: auth.activeAccount == AccountMode.buyer,
              onTap: () => _select(context, AccountMode.buyer),
            ),
            const SizedBox(height: 8),
            _AccountTile(
              mode: AccountMode.seller,
              title: _sellerTitle(user),
              subtitle: 'Seller account',
              imageUrl: user?.avatarUrl ?? '',
              selected: auth.activeAccount == AccountMode.seller,
              onTap: () => _select(context, AccountMode.seller),
            ),
          ],
        ),
      ),
    );
  }

  String _sellerTitle(AuthUser? user) {
    final shop = user?.shopName?.trim();
    if (shop != null && shop.isNotEmpty) return shop;
    if (user != null && user.name.isNotEmpty) return user.name;
    return 'Seller account';
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({
    required this.mode,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.selected,
    required this.onTap,
  });

  final AccountMode mode;
  final String title;
  final String subtitle;
  final String imageUrl;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final icon = mode == AccountMode.seller
        ? Icons.storefront_rounded
        : Icons.shopping_bag_outlined;

    return Material(
      color: selected ? AppColors.primaryLight : AppColors.surfaceVariant,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Stack(
                children: [
                  ThriftAvatar(imageUrl: imageUrl, name: title, size: 48),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.surface,
                          width: 1.5,
                        ),
                      ),
                      child: Icon(icon, color: Colors.white, size: 10),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTypography.subheading.copyWith(fontSize: 15),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(subtitle, style: AppTypography.caption),
                  ],
                ),
              ),
              if (selected)
                const Icon(Icons.check_circle_rounded, color: AppColors.primary)
              else
                const Icon(
                  Icons.radio_button_unchecked,
                  color: AppColors.textHint,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
