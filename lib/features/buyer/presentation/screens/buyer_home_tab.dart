import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/data/mock_data.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../providers/cart_provider.dart';
import '../../../../providers/data_provider.dart';
import '../../../../widgets/product_card.dart';
import '../../../../widgets/thrift_widgets.dart';

class BuyerHomeTab extends StatefulWidget {
  const BuyerHomeTab({super.key});

  @override
  State<BuyerHomeTab> createState() => _BuyerHomeTabState();
}

class _BuyerHomeTabState extends State<BuyerHomeTab> {
  int _bannerIndex = 0;
  final PageController _pageController = PageController();

  static const _banners = <_BannerData>[
    _BannerData(
      imageUrl:
          'https://images.unsplash.com/photo-1567401893414-76b7b1e5a7a5?w=900&h=500&fit=crop&q=85',
      title: 'Mega Thrift Sale',
      subtitle: 'Up to 70% off pre-loved fashion',
      cta: 'Shop Now',
      gradientStart: Color(0xFF0D9488),
      gradientEnd: Color(0xFF0F766E),
    ),
    _BannerData(
      imageUrl:
          'https://images.unsplash.com/photo-1558618666-fcd25c85cd64?w=900&h=500&fit=crop&q=85',
      title: 'New Arrivals',
      subtitle: 'Fresh drops from verified sellers daily',
      cta: 'Browse New',
      gradientStart: Color(0xFFF97316),
      gradientEnd: Color(0xFFEA580C),
    ),
    _BannerData(
      imageUrl:
          'https://images.unsplash.com/photo-1441984904996-e0b6ba687e04?w=900&h=500&fit=crop&q=85',
      title: 'Verified Sellers',
      subtitle: 'Authentic items, trusted community',
      cta: 'Explore',
      gradientStart: Color(0xFF1E293B),
      gradientEnd: Color(0xFF334155),
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final data = context.watch<DataProvider>();
    final cart = context.watch<CartProvider>();
    final notifCount =
        data.unreadNotificationCount(auth.user?.id ?? 'buyer_maya');

    final trendingProducts = data.trendingProducts;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          strokeWidth: 2.5,
          onRefresh: () async {
            await Future<void>.delayed(const Duration(milliseconds: 600));
            setState(() {});
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // ──────────────────────────────────────────────────────────────
              // Top Navigation Header (Search, Favorite, Bag)
              // ──────────────────────────────────────────────────────────────
              SliverToBoxAdapter(
                child: _TopHeader(
                  notifCount: notifCount,
                  cartCount: cart.itemCount,
                  onSearchTap: () => context.push(RouteNames.search),
                  onNotificationTap: () => context.push(RouteNames.notifications),
                  onBagTap: () => context.push(RouteNames.checkout),
                ),
              ),

              // ──────────────────────────────────────────────────────────────
              // Featured Banners
              // ──────────────────────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Column(
                    children: [
                      SizedBox(
                        height: 186,
                        child: PageView.builder(
                          controller: _pageController,
                          itemCount: _banners.length,
                          onPageChanged: (i) =>
                              setState(() => _bannerIndex = i),
                          itemBuilder: (_, i) => Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: _BannerCard(data: _banners[i]),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      _PageIndicator(
                        count: _banners.length,
                        current: _bannerIndex,
                      ),
                    ],
                  ),
                ),
              ),

              // ──────────────────────────────────────────────────────────────
              // Ending Soon Auctions
              // ──────────────────────────────────────────────────────────────
              SliverToBoxAdapter(
                child: _SectionHeader(
                  title: 'Ending Soon',
                  actionLabel: 'See all',
                  onActionTap: () {},
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 290,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: data.endingSoonBids.take(5).length,
                    itemBuilder: (_, i) {
                      final p = data.endingSoonBids[i];
                      return SizedBox(
                        width: 175,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: ProductCard(
                            product: p,
                            showCountdown: true,
                            compact: true,
                            onTap: () => context.push('/product/${p.id}'),
                            onSellerTap: () => context.push('/seller-profile/${p.sellerUsername}'),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),

              // ──────────────────────────────────────────────────────────────
              // Trending Products Grid
              // ──────────────────────────────────────────────────────────────
              SliverToBoxAdapter(
                child: _SectionHeader(
                  title: 'Trending Now',
                  actionLabel: null,
                  onActionTap: null,
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    childAspectRatio: 0.52,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (_, i) {
                      if (i >= trendingProducts.length) return null;
                      final p = trendingProducts[i];
                      return ProductCard(
                        product: p,
                        onTap: () => context.push('/product/${p.id}'),
                        onSellerTap: () => context.push('/seller-profile/${p.sellerUsername}'),
                      );
                    },
                    childCount: trendingProducts.length,
                  ),
                ),
              ),

              // ──────────────────────────────────────────────────────────────
              // Verified Sellers
              // ──────────────────────────────────────────────────────────────
              SliverToBoxAdapter(
                child: _SectionHeader(
                  title: 'Verified Sellers',
                  actionLabel: null,
                  onActionTap: null,
                ),
              ),
              SliverToBoxAdapter(
                child: _VerifiedSellersList(),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 36)),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Top Header (Search, Favorite, Cart/Bag)
// =============================================================================

class _TopHeader extends StatelessWidget {
  const _TopHeader({
    required this.notifCount,
    required this.cartCount,
    required this.onSearchTap,
    required this.onNotificationTap,
    required this.onBagTap,
  });

  final int notifCount;
  final int cartCount;
  final VoidCallback onSearchTap;
  final VoidCallback onNotificationTap;
  final VoidCallback onBagTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Expanded Search Bar
          Expanded(
            child: GestureDetector(
              onTap: onSearchTap,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.border.withValues(alpha: 0.7)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.search_rounded, color: AppColors.textHint, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "Search vintage, streetwear...",
                        style: AppTypography.body.copyWith(
                          color: AppColors.textHint,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          const SizedBox(width: 12),
          
          // Notification Icon
          IconButton(
            onPressed: onNotificationTap,
            icon: Badge(
              isLabelVisible: notifCount > 0,
              label: Text(notifCount.toString()),
              backgroundColor: AppColors.primary,
              child: const Icon(Icons.notifications_none_rounded),
            ),
            color: AppColors.textPrimary,
            iconSize: 26,
            constraints: const BoxConstraints(),
            padding: const EdgeInsets.all(4),
          ),
          
          const SizedBox(width: 10),
          
          // Bag / Cart Icon
          IconButton(
            onPressed: onBagTap,
            icon: Badge(
              isLabelVisible: cartCount > 0,
              label: Text(cartCount.toString()),
              backgroundColor: AppColors.secondary,
              child: const Icon(Icons.shopping_bag_outlined),
            ),
            color: AppColors.textPrimary,
            iconSize: 26,
            constraints: const BoxConstraints(),
            padding: const EdgeInsets.all(4),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Banner data model
// =============================================================================

class _BannerData {
  const _BannerData({
    required this.imageUrl,
    required this.title,
    required this.subtitle,
    required this.cta,
    required this.gradientStart,
    required this.gradientEnd,
  });

  final String imageUrl;
  final String title;
  final String subtitle;
  final String cta;
  final Color gradientStart;
  final Color gradientEnd;
}

// =============================================================================
// Banner Card
// =============================================================================

class _BannerCard extends StatelessWidget {
  const _BannerCard({required this.data});
  final _BannerData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: data.gradientStart.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Background fashion image
            CachedNetworkImage(
              imageUrl: data.imageUrl,
              fit: BoxFit.cover,
              placeholder: (_, _) => Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [data.gradientStart, data.gradientEnd],
                  ),
                ),
              ),
              errorWidget: (_, _, _) => Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [data.gradientStart, data.gradientEnd],
                  ),
                ),
              ),
            ),

            // Left-side gradient overlay for text legibility
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    data.gradientStart.withValues(alpha: 0.90),
                    data.gradientStart.withValues(alpha: 0.55),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),

            // Content
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    data.title,
                    style: AppTypography.heading.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 22,
                      letterSpacing: -0.4,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    data.subtitle,
                    style: AppTypography.caption.copyWith(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 14),
                  // CTA button
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          data.cta,
                          style: AppTypography.label.copyWith(
                            color: data.gradientStart,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Icon(Icons.arrow_forward_rounded,
                            size: 13, color: data.gradientStart),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Page Indicator Dots
// =============================================================================

class _PageIndicator extends StatelessWidget {
  const _PageIndicator({required this.count, required this.current});
  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final active = current == i;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeInOut,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: active ? 22 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: active ? AppColors.primary : AppColors.border,
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }
}

// =============================================================================
// Section Header
// =============================================================================

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    this.actionLabel,
    this.onActionTap,
  });
  final String title;
  final String? actionLabel;
  final VoidCallback? onActionTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 12),
      child: Row(
        children: [
          Text(title, style: AppTypography.heading),
          const Spacer(),
          if (actionLabel != null && onActionTap != null)
            GestureDetector(
              onTap: onActionTap,
              child: Text(
                actionLabel!,
                style: AppTypography.label.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// =============================================================================
// Verified Sellers horizontal list
// =============================================================================

class _VerifiedSellersList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 136,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: MockData.sellers.length,
        itemBuilder: (_, i) {
          final s = MockData.sellers[i];
          return Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Container(
              width: 230,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(18),
                border:
                    Border.all(color: AppColors.border.withValues(alpha: 0.6)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () {},
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        // Avatar with verified badge overlay
                        Stack(
                          children: [
                            ThriftAvatar(imageUrl: s.avatarUrl, size: 52),
                            if (s.isVerified)
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: Container(
                                  width: 18,
                                  height: 18,
                                  decoration: const BoxDecoration(
                                    color: AppColors.primary,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.check_rounded,
                                      color: Colors.white, size: 11),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(width: 12),
                        // Shop info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                s.shopName,
                                style: AppTypography.body.copyWith(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 3),
                              Row(
                                children: [
                                  const Icon(Icons.star_rounded,
                                      size: 13,
                                      color: Color(0xFFF59E0B)),
                                  const SizedBox(width: 2),
                                  Text(
                                    '${s.rating}',
                                    style: AppTypography.caption.copyWith(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 11,
                                    ),
                                  ),
                                  Text('  ·  ',
                                      style: AppTypography.caption
                                          .copyWith(fontSize: 11)),
                                  Text(
                                    '${s.itemCount} items',
                                    style: AppTypography.caption
                                        .copyWith(fontSize: 11),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryLight,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '${s.distanceKm} km away',
                                  style: AppTypography.caption.copyWith(
                                    color: AppColors.primaryDark,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
