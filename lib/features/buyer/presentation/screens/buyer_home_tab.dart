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
import '../../controllers/home_controller.dart';
import '../widgets/home_section_widgets.dart';
import '../widgets/verified_seller_card.dart';

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
    final textScale = MediaQuery.textScalerOf(context).scale(1);

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
              SliverToBoxAdapter(
                child: _TopHeader(
                  notifCount: notifCount,
                  cartCount: cart.itemCount,
                  onSearchTap: () => context.push(RouteNames.search),
                  onNotificationTap: () =>
                      context.push(RouteNames.notifications),
                  onBagTap: () => context.push(RouteNames.cart),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Column(
                    children: [
                      SizedBox(
                        height: 168,
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
              if (home.isOffline || home.showingCachedData)
                SliverToBoxAdapter(
                  child: HomeOfflineBanner(cached: home.showingCachedData),
                ),
              if (home.isLoading && !home.hasAnyContent) ...[
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.only(top: 20),
                    child: HomeRailShimmer(),
                  ),
                ),
                const SliverToBoxAdapter(child: HomeGridShimmer()),
              ] else if (home.hasError && !home.hasAnyContent) ...[
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _HomeErrorState(
                    message: home.errorMessage!,
                    onRetry: () => context.read<HomeController>().refresh(),
                  ),
                ),
              ] else if (!home.isLoading && !home.hasAnyContent) ...[
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: _HomeEmptyState(),
                ),
              ] else ...[
                SliverToBoxAdapter(
                  child: HomeSectionHeader(
                    title: 'Ending Soon',
                    topPadding: 22,
                    onSeeAll: () => context.push(RouteNames.homeEndingSoon),
                  ),
                ),
                SliverToBoxAdapter(
                  child: HomeSectionStatus(
                    section: home.endingSoon,
                    emptyMessage:
                        'No auctions wrapping up right now. Check back soon.',
                    onRetry: () => context.read<HomeController>().refresh(),
                    child: HomeProductRail(
                      products: home.endingSoonProducts.take(8).toList(),
                      cartCounts: home.cartCounts,
                      showCountdown: true,
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: HomeSectionHeader(
                    title: 'Suggested for You',
                    topPadding: 32,
                    onSeeAll: () => context.push(RouteNames.homeSuggested),
                  ),
                ),
                if (home.suggested.isLoading && home.suggestedProducts.isEmpty)
                  const SliverToBoxAdapter(child: HomeGridShimmer())
                else if (home.suggested.hasError &&
                    home.suggestedProducts.isEmpty)
                  SliverToBoxAdapter(
                    child: HomeInlineError(
                      message: home.suggested.errorMessage!,
                      onRetry: () => context.read<HomeController>().refresh(),
                    ),
                  )
                else if (home.suggested.isEmpty)
                  const SliverToBoxAdapter(
                    child: HomeInlineEmpty(
                      message:
                          'No listings to suggest yet. Fresh drops will show up here.',
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverGrid(
                      gridDelegate: ProductCard.gridDelegateFor(
                        maxWidth: MediaQuery.sizeOf(context).width,
                        compact: true,
                        textScale: textScale,
                      ),
                      delegate: SliverChildBuilderDelegate((_, i) {
                        final p = home.suggestedProducts[i];
                        return ProductCard(
                          product: p,
                          compact: true,
                          cartAddCount: home.cartCounts[p.id],
                          onTap: () => context.push('/product/${p.id}'),
                        );
                      }, childCount: home.suggestedProducts.length),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: HomeSectionHeader(
                    title: 'Bidding Products',
                    topPadding: 36,
                    onSeeAll: () => context.push(RouteNames.homeBidding),
                  ),
                ),
                SliverToBoxAdapter(
                  child: HomeSectionStatus(
                    section: home.bidding,
                    emptyMessage: 'No live auctions right now.',
                    onRetry: () => context.read<HomeController>().refresh(),
                    child: HomeProductRail(
                      products: home.biddingProducts.take(8).toList(),
                      cartCounts: home.cartCounts,
                      showCountdown: true,
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: HomeSectionHeader(
                    title: 'Verified Sellers',
                    topPadding: 36,
                    onSeeAll: () =>
                        context.push(RouteNames.homeVerifiedSellers),
                  ),
                ),
                SliverToBoxAdapter(
                  child: HomeSectionStatus(
                    section: home.verifiedSellersSection,
                    emptyMessage: 'No verified shops to show yet.',
                    onRetry: () => context.read<HomeController>().refresh(),
                    shimmer: const SizedBox(
                      height: 96,
                      child: HomeRailShimmer(),
                    ),
                    child: SizedBox(
                      height: 108,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: home.verifiedSellers.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 10),
                        itemBuilder: (_, i) => VerifiedSellerCard(
                          seller: home.verifiedSellers[i],
                          compact: true,
                        ),
                      ),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 40)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

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
        children: [
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
                        'Search vintage, streetwear...',
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

class _BannerCard extends StatelessWidget {
  const _BannerCard({required this.data});
  final _BannerData data;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Stack(
        fit: StackFit.expand,
        children: [
          CachedNetworkImage(
            imageUrl: data.imageUrl,
            fit: BoxFit.cover,
            memCacheWidth: 900,
            placeholder: (_, _) => ColoredBox(color: data.gradientStart),
            errorWidget: (_, _, _) => ColoredBox(color: data.gradientStart),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  data.gradientStart.withValues(alpha: 0.90),
                  data.gradientStart.withValues(alpha: 0.50),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.48, 1.0],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  data.title,
                  style: AppTypography.heading.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  data.subtitle,
                  style: AppTypography.caption.copyWith(
                    color: Colors.white.withValues(alpha: 0.88),
                    fontSize: 12.5,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

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
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Check back later for fresh drops from verified sellers.',
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
          Icon(
            Icons.wifi_off_rounded,
            size: 40,
            color: AppColors.error.withValues(alpha: 0.7),
          ),
          const SizedBox(height: 20),
          Text(
            'Something went wrong',
            style: AppTypography.subheading.copyWith(
              fontWeight: FontWeight.w700,
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
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Retry'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }
}
