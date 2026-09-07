import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../providers/cart_provider.dart';
import '../../../../providers/notifications_provider.dart';
import '../../../../widgets/product_card.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../controllers/home_controller.dart';

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
    final home = context.watch<HomeController>();
    final cart = context.watch<CartProvider>();
    final notifCount = context.watch<NotificationsProvider>().unreadCount;

    final trendingProducts = home.trendingProducts;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          strokeWidth: 2.5,
          onRefresh: () => context.read<HomeController>().refresh(),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
              // Top Navigation Header (Search, Favorite, Bag)
              // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
              SliverToBoxAdapter(
                child: _TopHeader(
                  notifCount: notifCount,
                  cartCount: cart.itemCount,
                  onSearchTap: () => context.push(RouteNames.search),
                  onNotificationTap: () =>
                      context.push(RouteNames.notifications),
                  onBagTap: () => context.push(RouteNames.checkout),
                ),
              ),

              // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
              // Featured Banners
              // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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

              // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
              // Loading / Error / Content states
              // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
              if (home.isLoading && home.products.isEmpty) ...[
                // Shimmer loading state
                const SliverToBoxAdapter(child: _HomeLoadingShimmer()),
              ] else if (home.hasError && home.products.isEmpty) ...[
                // Error state
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _HomeErrorState(
                    message: home.errorMessage!,
                    onRetry: () => context.read<HomeController>().refresh(),
                  ),
                ),
              ] else if (!home.isLoading && home.products.isEmpty) ...[
                // Empty state
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: _HomeEmptyState(),
                ),
              ] else ...[
                // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                // Ending Soon Auctions
                // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                if (home.endingSoonProducts.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: _SectionHeader(
                      title: 'Ending Soon',
                      actionLabel: 'See all',
                      onActionTap: () {},
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 245,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: home.endingSoonProducts.take(5).length,
                        itemBuilder: (_, i) {
                          final p = home.endingSoonProducts[i];
                          return SizedBox(
                            width: 152,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 10),
                              child: ProductCard(
                                product: p,
                                showCountdown: true,
                                compact: true,
                                onTap: () => context.push('/product/${p.id}'),
                                onSellerTap: () => context.push(
                                  '/seller-profile/${p.sellerUsername}',
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],

                // ─────────────────────────────────────────────────────────────
                // Trending Products Grid
                // ─────────────────────────────────────────────────────────────
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
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.67,
                        ),
                    delegate: SliverChildBuilderDelegate((_, i) {
                      if (i >= trendingProducts.length) return null;
                      final p = trendingProducts[i];
                      return ProductCard(
                        product: p,
                        compact: true,
                        onTap: () => context.push('/product/${p.id}'),
                        onSellerTap: () =>
                            context.push('/seller-profile/${p.sellerUsername}'),
                      );
                    }, childCount: trendingProducts.length),
                  ),
                ),

                // ─────────────────────────────────────────────────────────────
                // Verified Sellers (from Supabase)
                // ─────────────────────────────────────────────────────────────
                if (home.verifiedSellers.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: _SectionHeader(
                      title: 'Verified Sellers',
                      actionLabel: null,
                      onActionTap: null,
                    ),
                  ),
                  SliverToBoxAdapter(child: _VerifiedSellersList()),
                ],

                const SliverToBoxAdapter(child: SizedBox(height: 36)),
              ],
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
          // Drawer Menu Button
          Builder(
            builder: (ctx) => IconButton(
              icon: const Icon(Icons.menu_rounded),
              color: AppColors.textPrimary,
              iconSize: 26,
              onPressed: () => Scaffold.of(ctx).openDrawer(),
              tooltip: 'Open menu',
              constraints: const BoxConstraints(),
              padding: const EdgeInsets.only(right: 6),
            ),
          ),
          // Expanded Search Bar
          Expanded(
            child: GestureDetector(
              onTap: onSearchTap,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppColors.border.withValues(alpha: 0.7),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.search_rounded,
                      color: AppColors.textHint,
                      size: 22,
                    ),
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
                      horizontal: 16,
                      vertical: 8,
                    ),
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
                        Icon(
                          Icons.arrow_forward_rounded,
                          size: 13,
                          color: data.gradientStart,
                        ),
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
    final home = context.watch<HomeController>();
    final sellers = home.verifiedSellers;

    if (sellers.isEmpty) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: 116,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: sellers.length,
        itemBuilder: (_, i) {
          final s = sellers[i];
          final targetRoute = '/seller-profile/${s.username.isNotEmpty ? s.username : (s.sellerId ?? '')}';
          return Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Container(
              width: 220,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.border.withValues(alpha: 0.6),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => context.push(targetRoute),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        // Avatar with verified badge overlay
                        Stack(
                          children: [
                            ThriftAvatar(imageUrl: s.avatarUrl, size: 46),
                            if (s.isVerified)
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: Container(
                                  width: 17,
                                  height: 17,
                                  decoration: const BoxDecoration(
                                    color: AppColors.primary,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.check_rounded,
                                    color: Colors.white,
                                    size: 10.5,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(width: 11),
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
                                  fontSize: 12.5,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 3),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.star_rounded,
                                    size: 13,
                                    color: Color(0xFFF59E0B),
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    s.rating > 0 ? s.rating.toStringAsFixed(1) : '5.0',
                                    style: AppTypography.caption.copyWith(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 10.5,
                                    ),
                                  ),
                                  Text(
                                    ' · ',
                                    style: AppTypography.caption.copyWith(
                                      fontSize: 10.5,
                                      color: AppColors.textHint,
                                    ),
                                  ),
                                  Text(
                                    '${s.itemCount} ${s.itemCount == 1 ? 'item' : 'items'}',
                                    style: AppTypography.caption.copyWith(
                                      fontSize: 10.5,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 5),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryLight,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.verified_rounded,
                                      size: 11,
                                      color: AppColors.primary,
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      'Verified Seller',
                                      style: AppTypography.caption.copyWith(
                                        color: AppColors.primaryDark,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 9.5,
                                      ),
                                    ),
                                  ],
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

// =============================================================================
// Loading Shimmer â€” skeleton grid shown while products load from Supabase
// =============================================================================

class _HomeLoadingShimmer extends StatelessWidget {
  const _HomeLoadingShimmer();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Fake section header
          Container(
            width: 130,
            height: 18,
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(height: 16),
          // 2Ã—2 shimmer grid
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 4,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 0.52,
            ),
            itemBuilder: (_, _) => _ShimmerCard(),
          ),
        ],
      ),
    );
  }
}

class _ShimmerCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image placeholder
          Expanded(
            flex: 5,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant.withValues(alpha: 0.6),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(18),
                ),
              ),
              child: Center(
                child: Icon(
                  Icons.image_outlined,
                  color: AppColors.textHint.withValues(alpha: 0.3),
                  size: 36,
                ),
              ),
            ),
          ),
          // Text placeholder lines
          Expanded(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 50,
                    height: 10,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    height: 12,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: 80,
                    height: 12,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    width: 70,
                    height: 14,
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Empty State â€” shown when no active products exist in the database
// =============================================================================

class _HomeEmptyState extends StatelessWidget {
  const _HomeEmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.primaryLight.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.storefront_outlined,
              size: 40,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'No thrift items available yet',
            style: AppTypography.subheading.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Check back later for fresh drops\nfrom verified sellers!',
            style: AppTypography.body.copyWith(
              color: AppColors.textSecondary,
              fontSize: 14,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Error State â€” shown when fetching products from Supabase fails
// =============================================================================

class _HomeErrorState extends StatelessWidget {
  const _HomeErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.wifi_off_rounded,
              size: 40,
              color: AppColors.error.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Something went wrong',
            style: AppTypography.subheading.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: AppTypography.body.copyWith(
              color: AppColors.textSecondary,
              fontSize: 14,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: 140,
            child: OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
