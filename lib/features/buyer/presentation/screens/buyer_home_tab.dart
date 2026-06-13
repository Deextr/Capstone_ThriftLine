import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/data/mock_data.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../features/auth/data/auth_service.dart';
import '../../../../providers/auth_provider.dart';
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
  String _selectedCategory = 'All';

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final data = context.watch<DataProvider>();
    final user = AuthService().getUserByUsername(auth.username ?? '');
    final name = user?.name ?? 'there';
    final notifCount = data.unreadNotificationCount(auth.user?.id ?? 'buyer_maya');

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            await Future<void>.delayed(const Duration(milliseconds: 500));
            setState(() {});
          },
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(AppConstants.spacingMd),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text('${_greeting()}, $name! 👋', style: AppTypography.heading),
                          ),
                          Badge(
                            isLabelVisible: notifCount > 0,
                            label: Text('$notifCount'),
                            child: IconButton(
                              icon: const Icon(Icons.notifications_outlined),
                              onPressed: () => context.push(RouteNames.notifications),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.chat_bubble_outline),
                            onPressed: () => context.push(RouteNames.chat),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          const Icon(Icons.location_on, size: 16, color: AppColors.primary),
                          const SizedBox(width: 4),
                          Text(user?.location ?? 'Quezon City', style: AppTypography.caption),
                          const Icon(Icons.keyboard_arrow_down, size: 16),
                        ],
                      ),
                      const SizedBox(height: 16),
                      GestureDetector(
                        onTap: () => context.push(RouteNames.search),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.search, color: AppColors.textHint),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  "Try: 'vintage denim jacket size M under ₱500'",
                                  style: AppTypography.body.copyWith(color: AppColors.textHint),
                                ),
                              ),
                              GestureDetector(
                                onTap: () => showThriftSnackBar(context, 'Voice search coming soon'),
                                child: const Icon(Icons.mic, color: AppColors.primary),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 36,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: MockData.categoryChips.map((c) {
                            return ThriftChip(
                              label: c,
                              selected: _selectedCategory == c,
                              onTap: () => setState(() => _selectedCategory = c),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 140,
                        child: PageView(
                          onPageChanged: (i) => setState(() => _bannerIndex = i),
                          children: [
                            _banner('Mega Thrift Sale — Up to 70% off', [AppColors.primary, AppColors.primaryDark]),
                            _banner('New Arrivals Daily', [AppColors.secondary, const Color(0xFFEA580C)]),
                            _banner('Verified Sellers Only', [const Color(0xFF1E293B), const Color(0xFF334155)]),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(3, (i) => Container(
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: _bannerIndex == i ? 16 : 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: _bannerIndex == i ? AppColors.primary : AppColors.border,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        )),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
                  child: Text('Ending Soon Bids', style: AppTypography.heading),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 260,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: data.endingSoonBids.take(4).length,
                    itemBuilder: (_, i) {
                      final p = data.endingSoonBids[i];
                      return SizedBox(
                        width: 170,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: ProductCard(
                            product: p,
                            showCountdown: true,
                            onTap: () => context.push('/product/${p.id}'),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
                  child: Text('Nearby Sellers', style: AppTypography.heading),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 120,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: MockData.sellers.length,
                    itemBuilder: (_, i) {
                      final s = MockData.sellers[i];
                      return Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: ThriftCard(
                          child: SizedBox(
                            width: 200,
                            child: Row(
                              children: [
                                ThriftAvatar(imageUrl: s.avatarUrl, size: 48),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(s.shopName, style: AppTypography.body.copyWith(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                                      Text('${s.distanceKm} km • ⭐ ${s.rating}', style: AppTypography.caption),
                                      Text('${s.itemCount} items', style: AppTypography.caption),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
                  child: Text('Trending Now', style: AppTypography.heading),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.62,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (_, i) {
                      final products = _selectedCategory == 'All'
                          ? data.trendingProducts
                          : data.searchProducts('', category: _selectedCategory);
                      if (i >= products.length) return null;
                      final p = products[i];
                      return ProductCard(
                        product: p,
                        onTap: () => context.push('/product/${p.id}'),
                      );
                    },
                    childCount: _selectedCategory == 'All'
                        ? data.trendingProducts.length
                        : data.searchProducts('', category: _selectedCategory).length,
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _banner(String text, List<Color> colors) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: Text(text, style: AppTypography.subheading.copyWith(color: Colors.white), textAlign: TextAlign.center),
      ),
    );
  }
}
