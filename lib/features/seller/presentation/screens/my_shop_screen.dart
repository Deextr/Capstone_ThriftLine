import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../providers/auth_provider.dart';
import '../../../auth/domain/auth_user.dart';
import '../../../../widgets/product_card.dart';
import '../../../../widgets/skeleton_widgets.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../../trust_safety/data/review_rules.dart';
import '../../controllers/my_shop_controller.dart';
import '../widgets/my_shop_trust_panel.dart';

class MyShopScreen extends StatelessWidget {
  const MyShopScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final shop = context.watch<MyShopController>();
    final user = auth.user;
    final username = auth.username ?? '';
    final products = shop.previewProducts;
    final ratingLabel = formatRatingAverage(
      average: user?.rating,
      count: user?.ratingCount ?? 0,
    );
    final sold = shop.soldCount;
    final followers = shop.followerCount;
    final following = shop.followingCount;
    final loading = shop.isLoading && shop.products.isEmpty;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () => context.read<MyShopController>().load(),
          child: loading
              ? const _MyShopLoadingBody()
              : ListView(
                  padding: EdgeInsets.zero,
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    _ShopHeader(
                      user: user,
                      username: username,
                      ratingLabel: ratingLabel,
                      sold: sold,
                      followers: followers,
                      following: following,
                    ),
                    if (shop.errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppConstants.spacingMd,
                          0,
                          AppConstants.spacingMd,
                          12,
                        ),
                        child: _ShopErrorBanner(message: shop.errorMessage!),
                      ),
                    if (user != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppConstants.spacingMd,
                        ),
                        child: MyShopTrustPanel(user: user),
                      ),
                    const SizedBox(height: 20),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppConstants.spacingMd,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Active Listings',
                            style: AppTypography.subheading.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (products.isNotEmpty)
                            Text(
                              '${shop.activeCount} live',
                              style: AppTypography.caption.copyWith(
                                color: AppColors.textSecondary,
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
                              'No active listings yet',
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
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final textScale = MediaQuery.textScalerOf(
                              context,
                            ).scale(1);
                            return GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate: ProductCard.gridDelegateFor(
                                maxWidth: constraints.maxWidth,
                                horizontalPadding: 0,
                                compact: true,
                                textScale: textScale,
                              ),
                              itemCount: products.length,
                              itemBuilder: (_, i) => ProductCard(
                                product: products[i],
                                compact: true,
                                onTap: () => context.push(
                                  RouteNames.productFor(
                                    products[i].id,
                                    ownerPreview: true,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 32),
                  ],
                ),
        ),
      ),
    );
  }
}

class _ShopHeader extends StatelessWidget {
  const _ShopHeader({
    required this.user,
    required this.username,
    required this.ratingLabel,
    required this.sold,
    required this.followers,
    required this.following,
  });

  final AuthUser? user;
  final String username;
  final String ratingLabel;
  final int sold;
  final int followers;
  final int following;

  @override
  Widget build(BuildContext context) {
    final avatarUrl = context.watch<AuthProvider>().activeAvatarUrl;
    final bio = user?.bio?.trim();
    return Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              height: 120,
              width: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
            Positioned(
              top: 4,
              left: 4,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => context.pop(),
              ),
            ),
            Positioned(
              bottom: -40,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                  child: ThriftAvatar(
                    imageUrl: avatarUrl,
                    name: user?.shopName ?? user?.name,
                    size: 80,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 48),
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
                      user?.shopName ?? user?.name ?? 'My Shop',
                      style: AppTypography.heading.copyWith(fontSize: 22),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
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
              const SizedBox(height: 4),
              Text(
                '@$username',
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              if (user?.ratingCount == 0)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '$ratingLabel · $sold sold on ThriftLine',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '★ $ratingLabel · $sold sold on ThriftLine',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _StatColumn(value: ratingLabel, label: 'Rating'),
                  _StatColumn(value: '$followers', label: 'Followers'),
                  _StatColumn(value: '$sold', label: 'Sold'),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => context.push(RouteNames.followingShops),
                    child: _StatColumn(value: '$following', label: 'Following'),
                  ),
                ],
              ),
              if (bio != null && bio.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  bio,
                  style: AppTypography.body.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 16),
            ],
          ),
        ),
      ],
    );
  }
}

class _MyShopLoadingBody extends StatelessWidget {
  const _MyShopLoadingBody();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppConstants.spacingMd),
      children: const [
        SkeletonBox(width: double.infinity, height: 120, radius: 12),
        SizedBox(height: 48),
        Center(child: SkeletonCircle(size: 80)),
        SizedBox(height: 16),
        Center(child: SkeletonBox(width: 180, height: 22)),
        SizedBox(height: 8),
        Center(child: SkeletonBox(width: 120, height: 14)),
        SizedBox(height: 24),
        SkeletonBox(width: double.infinity, height: 220, radius: 16),
        SizedBox(height: 24),
        ProductGridSkeleton(itemCount: 4, padding: EdgeInsets.zero),
      ],
    );
  }
}

class _ShopErrorBanner extends StatelessWidget {
  const _ShopErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: AppColors.error, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: AppTypography.caption.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  const _StatColumn({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: AppTypography.subheading.copyWith(fontWeight: FontWeight.w700),
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
