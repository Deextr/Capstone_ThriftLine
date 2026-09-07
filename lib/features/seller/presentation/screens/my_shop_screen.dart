import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../providers/data_provider.dart';
import '../../../../widgets/product_card.dart';
import '../../../../widgets/thrift_widgets.dart';

class MyShopScreen extends StatelessWidget {
  const MyShopScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final data = context.watch<DataProvider>();
    final user = auth.user;
    final username = auth.username ?? '';
    final products = data.productsForSeller(username).take(6).toList();
    final rating = data.sellerRating(username);
    final sold = data.soldCount(username);
    final followers = data.followersCount(username);
    final following = data.followingCount(username);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            // â”€â”€ Cover Banner â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  height: 130,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.primary,
                        AppColors.primaryDark,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),

                // Back button
                Positioned(
                  top: 8,
                  left: 8,
                  child: IconButton(
                    icon: const Icon(
                      Icons.arrow_back,
                      color: Colors.white,
                    ),
                    onPressed: () => context.pop(),
                  ),
                ),

                // Avatar overlapping banner
                Positioned(
                  bottom: -44,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: ThriftAvatar(
                      imageUrl: user?.avatarUrl ?? '',
                      name: user?.shopName ?? user?.name,
                      size: 88,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 52),

            // â”€â”€ Shop Name & Verification â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.spacingMd,
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          user?.shopName ?? user?.name ?? '',
                          style: AppTypography.heading.copyWith(
                            fontSize: 22,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (user?.isVerified == true) ...[
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.verified,
                          color: AppColors.primary,
                          size: 22,
                        ),
                      ],
                    ],
                  ),

                  const SizedBox(height: 2),

                  Text(
                    '@$username',
                    style: AppTypography.caption.copyWith(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),

                  const SizedBox(height: 4),

                  Text(
                    'â­ ${rating.toStringAsFixed(1)}  â€¢  $sold sales',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Trust badge
                  if (user != null)
                    SellerTrustBadge(
                      trustScore: user.trustScore,
                      isVerified: user.isVerified,
                      shopName: user.shopName ?? user.name,
                    ),

                  const SizedBox(height: 16),

                  // Stats row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _StatColumn(
                        value: '${rating.toStringAsFixed(1)} â˜…',
                        label: 'Rating',
                      ),
                      const _Divider(),
                      _StatColumn(
                        value: '$sold',
                        label: 'Sold',
                      ),
                      const _Divider(),
                      _StatColumn(
                        value: '$followers',
                        label: 'Followers',
                      ),
                      const _Divider(),
                      _StatColumn(
                        value: '$following',
                        label: 'Following',
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Edit Shop button
                  ThriftButton(
                    label: 'Edit Shop',
                    variant: ThriftButtonVariant.outline,
                    expand: false,
                    onPressed: () => showThriftSnackBar(
                      context,
                      'Coming soon',
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Bio
                  Text(
                    'Curated vintage and Y2K fashion finds.',
                    style: AppTypography.body.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 12),

                  // Tags
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    alignment: WrapAlignment.center,
                    children: [
                      'Vintage',
                      'Y2K',
                      'Tops',
                      'Denim',
                    ]
                        .map(
                          (t) => ThriftBadge(label: t),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // â”€â”€ Active Listings â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.spacingMd,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Active Listings',
                    style: AppTypography.subheading,
                  ),
                  if (products.isNotEmpty)
                    TextButton(
                      onPressed: () => showThriftSnackBar(
                        context,
                        'Coming soon',
                      ),
                      child: Text(
                        'See all',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            if (products.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppConstants.spacingMd,
                  vertical: 32,
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.storefront_outlined,
                      size: 48,
                      color: AppColors.textHint,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No listings yet',
                      style: AppTypography.body.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ThriftButton(
                      label: 'Add a Listing',
                      variant: ThriftButtonVariant.primary,
                      expand: false,
                      onPressed: () =>
                          context.push(RouteNames.addListing),
                    ),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppConstants.spacingMd,
                ),
                child: GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.65,
                  ),
                  itemCount: products.length,
                  itemBuilder: (_, i) => ProductCard(
                    product: products[i],
                    onTap: () => context.push(
                      '/product/${products[i].id}',
                    ),
                  ),
                ),
              ),

            const SizedBox(height: 28),

            // â”€â”€ Shop Settings â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.spacingMd,
              ),
              child: Text(
                'Shop Settings',
                style: AppTypography.subheading,
              ),
            ),

            const SizedBox(height: 8),

            _SettingsCard(
              children: [
                _MenuTile(
                  icon: Icons.store_outlined,
                  label: 'Shop Details',
                  onTap: () => showThriftSnackBar(
                    context,
                    'Coming soon',
                  ),
                ),
                _MenuTile(
                  icon: Icons.payment_outlined,
                  label: 'Payment Details',
                  onTap: () => showThriftSnackBar(
                    context,
                    'Coming soon',
                  ),
                ),
                _MenuTile(
                  icon: Icons.local_shipping_outlined,
                  label: 'Shipping Preferences',
                  onTap: () => showThriftSnackBar(
                    context,
                    'Coming soon',
                  ),
                ),
                _MenuTile(
                  icon: Icons.menu_book_outlined,
                  label: 'Seller Guidelines',
                  onTap: () => showThriftSnackBar(
                    context,
                    'Coming soon',
                  ),
                ),
              ],
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Helper Widgets
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _StatColumn extends StatelessWidget {
  const _StatColumn({
    required this.value,
    required this.label,
  });

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: AppTypography.subheading.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: AppTypography.caption.copyWith(
            color: AppColors.textSecondary,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      width: 1,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      color: AppColors.border,
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.children,
  });

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spacingMd,
      ),
      child: Material(
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
            child: Column(
              children: children,
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
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
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 4,
      ),
      leading: Icon(
        icon,
        color: AppColors.textPrimary,
        size: 22,
      ),
      title: Text(
        label,
        style: AppTypography.body,
      ),
      trailing: const Icon(
        Icons.chevron_right,
        size: 20,
        color: AppColors.textHint,
      ),
      onTap: onTap,
    );
  }
}

