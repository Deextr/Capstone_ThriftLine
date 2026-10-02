import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/utils/seller_trust.dart';
import '../../../../models/enums.dart';
import '../../../../models/product_model.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../data/followed_shop_item.dart';

class FollowedShopCard extends StatelessWidget {
  const FollowedShopCard({
    super.key,
    required this.shop,
    required this.isFollowing,
    required this.onToggleFollow,
  });

  final FollowedShopItem shop;
  final bool isFollowing;
  final VoidCallback onToggleFollow;

  @override
  Widget build(BuildContext context) {
    final currencyFormatter = NumberFormat.currency(
      locale: 'en_PH',
      symbol: '₱',
      decimalDigits: 0,
    );

    final label = resolveTrustLabel(
      score: shop.trustScore,
      storedLevel: shop.trustLevel,
    );
    final trustData = trustClassifications.firstWhere(
      (c) => c.label == label,
      orElse: () => trustClassifications.first,
    );

    void openShop() {
      context.push(
        RouteNames.sellerProfile.replaceFirst(
          ':username',
          shop.username,
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: openShop,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          // ── Header: Avatar, Name, Location, Follow Toggle ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => context.push(
                    RouteNames.sellerProfile.replaceFirst(
                      ':username',
                      shop.username,
                    ),
                  ),
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      ThriftAvatar(
                        imageUrl: shop.avatarUrl,
                        name: shop.shopName,
                        size: 52,
                      ),
                      if (shop.isVerified)
                        Container(
                          padding: const EdgeInsets.all(2.5),
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check_rounded,
                            color: Colors.white,
                            size: 11,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: () => context.push(
                          RouteNames.sellerProfile.replaceFirst(
                            ':username',
                            shop.username,
                          ),
                        ),
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                shop.shopName,
                                style: AppTypography.heading.copyWith(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (shop.isVerified) ...[
                              const SizedBox(width: 4),
                              const Icon(
                                Icons.verified,
                                color: AppColors.primary,
                                size: 16,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              '@${shop.username}',
                              style: AppTypography.caption.copyWith(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (shop.location.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            const Text(
                              '•',
                              style: TextStyle(
                                color: AppColors.textHint,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.location_on_outlined,
                              size: 13,
                              color: AppColors.textSecondary,
                            ),
                            const SizedBox(width: 2),
                            Flexible(
                              child: Text(
                                shop.location,
                                style: AppTypography.caption.copyWith(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      // Rating & Sales & Trust
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          if (shop.ratingCount > 0)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.star_rounded,
                                  size: 16,
                                  color: Color(0xFFFFB800),
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  '${shop.rating.toStringAsFixed(1)} (${shop.ratingCount})',
                                  style: AppTypography.caption.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          if (shop.sales > 0)
                            Text(
                              '${shop.sales} sold',
                              style: AppTypography.caption.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          // Trust score chip
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: trustData.color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  trustData.icon,
                                  size: 12,
                                  color: trustData.color,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  '${shop.trustScore} Trust',
                                  style: AppTypography.caption.copyWith(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: trustData.color,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Follow / Unfollow Button
                _FollowToggleButton(
                  isFollowing: isFollowing,
                  onPressed: onToggleFollow,
                ),
              ],
            ),
          ),

          // ── Shop Bio snippet ──
          if (shop.shopBio != null && shop.shopBio!.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
              child: Text(
                shop.shopBio!.trim(),
                style: AppTypography.body.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  height: 1.35,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),

          // ── Preview Products Row ──
          if (shop.previewProducts.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Recent Listings',
                    style: AppTypography.caption.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                      letterSpacing: 0.3,
                    ),
                  ),
                  if (shop.itemCount > shop.previewProducts.length)
                    Text(
                      '${shop.itemCount} items',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textHint,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(
              height: 112,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: shop.previewProducts.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final product = shop.previewProducts[index];
                  return _ProductThumbnail(
                    product: product,
                    currencyFormatter: currencyFormatter,
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
          ] else ...[
            const SizedBox(height: 4),
          ],
        ],
      ),
    ),
  ),
);
  }
}

class _FollowToggleButton extends StatelessWidget {
  const _FollowToggleButton({
    required this.isFollowing,
    required this.onPressed,
  });

  final bool isFollowing;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isFollowing
                ? AppColors.primaryLight.withValues(alpha: 0.7)
                : AppColors.primary,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isFollowing ? AppColors.primary : Colors.transparent,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isFollowing ? Icons.check_rounded : Icons.add_rounded,
                size: 14,
                color: isFollowing ? AppColors.primaryDark : Colors.white,
              ),
              const SizedBox(width: 4),
              Text(
                isFollowing ? 'Following' : 'Follow',
                style: AppTypography.caption.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: isFollowing ? AppColors.primaryDark : Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductThumbnail extends StatelessWidget {
  const _ProductThumbnail({
    required this.product,
    required this.currencyFormatter,
  });

  final ProductModel product;
  final NumberFormat currencyFormatter;

  @override
  Widget build(BuildContext context) {
    final hasImage = product.imageUrls.isNotEmpty;
    final price = product.sellingType == SellingType.auction
        ? (product.currentBid ?? product.startingBid ?? product.price)
        : product.price;

    return GestureDetector(
      onTap: () => context.push(
        RouteNames.product.replaceFirst(':id', product.id),
      ),
      child: Container(
        width: 84,
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (hasImage)
                CachedNetworkImage(
                  imageUrl: product.imageUrls.first,
                  fit: BoxFit.cover,
                  placeholder: (_, _) => Container(
                    color: AppColors.surfaceVariant,
                    child: const Center(
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ),
                  errorWidget: (_, _, _) => Container(
                    color: AppColors.surfaceVariant,
                    child: const Icon(
                      Icons.image_not_supported_outlined,
                      size: 20,
                      color: AppColors.textHint,
                    ),
                  ),
                )
              else
                Container(
                  color: AppColors.surfaceVariant,
                  child: const Icon(
                    Icons.shopping_bag_outlined,
                    size: 24,
                    color: AppColors.textHint,
                  ),
                ),
              // Price banner overlay
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.75),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Text(
                    currencyFormatter.format(price),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              if (product.sellingType == SellingType.auction)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 3,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.gavel_rounded,
                      size: 10,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
