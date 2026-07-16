import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../features/auth/data/auth_service.dart';
import '../../../../models/product_model.dart';
import '../../../../models/enums.dart';
import '../../../../providers/data_provider.dart';
import '../../../../widgets/thrift_widgets.dart';

class SellerPublicProfileScreen extends StatelessWidget {
  const SellerPublicProfileScreen({super.key, required this.username});

  final String username;

  @override
  Widget build(BuildContext context) {
    final seller = AuthService().getUserByUsername(username);
    if (seller == null) {
      return Scaffold(
        appBar: AppBar(leading: BackButton(onPressed: () => context.pop())),
        body: const Center(child: Text('Seller not found')),
      );
    }

    final data = context.watch<DataProvider>();
    final products = data.productsForSeller(username);
    final isFollowing = data.isFollowing(username);
    final followers = data.followersCount(username);
    final following = data.followingCount(username);
    final sold = data.soldCount(username);
    final reviews = data.reviewCount(username);
    final rating = data.sellerRating(username);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: _buildAppBar(context),
        body: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) {
            return [
              SliverToBoxAdapter(
                child: _buildProfileHeader(
                  context,
                  seller: seller,
                  rating: rating,
                  reviews: reviews,
                  sold: sold,
                  following: following,
                  followers: followers,
                  isFollowing: isFollowing,
                  data: data,
                ),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _SliverAppBarDelegate(
                  TabBar(
                    indicatorColor: AppColors.primary,
                    indicatorWeight: 2,
                    labelColor: AppColors.primary,
                    unselectedLabelColor: AppColors.textSecondary,
                    labelStyle: AppTypography.label.copyWith(fontWeight: FontWeight.w600),
                    tabs: const [
                      Tab(icon: Icon(Icons.grid_on)), // Shop Tab
                      Tab(icon: Icon(Icons.star_border)), // Reviews Tab
                    ],
                  ),
                ),
              ),
            ];
          },
          body: TabBarView(
            children: [
              // Shop tab (Grid)
              _buildProductGrid(context, products),

              // Reviews tab (Empty state)
              const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.rate_review_outlined, size: 48, color: AppColors.textHint),
                    SizedBox(height: 16),
                    Text('No reviews yet', style: TextStyle(color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // App Bar
  // ═══════════════════════════════════════════════════════════════════════════

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: AppColors.surface,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
        onPressed: () => context.pop(),
      ),
      title: Text(
        username,
        style: AppTypography.subheading.copyWith(fontWeight: FontWeight.w700),
      ),
      centerTitle: true,
      actions: [
        IconButton(
          icon: const Icon(Icons.favorite_border, color: AppColors.textPrimary, size: 22),
          onPressed: () => showThriftSnackBar(context, 'Seller saved!'),
        ),
        IconButton(
          icon: const Icon(Icons.shopping_bag_outlined, color: AppColors.textPrimary, size: 22),
          onPressed: () {},
        ),
        IconButton(
          icon: const Icon(Icons.more_vert, color: AppColors.textPrimary, size: 22),
          onPressed: () => _showMoreOptions(context),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Three-dot menu bottom sheet
  // ═══════════════════════════════════════════════════════════════════════════

  void _showMoreOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              _OptionTile(
                icon: Icons.share_outlined,
                label: 'Share',
                onTap: () {
                  Navigator.pop(ctx);
                  showThriftSnackBar(context, 'Link copied to clipboard!');
                },
              ),
              _OptionTile(
                icon: Icons.block,
                label: 'Block User',
                isDestructive: false,
                onTap: () {
                  Navigator.pop(ctx);
                  _showConfirmationDialog(
                    context,
                    title: 'Block User',
                    message: 'Are you sure you want to block this user? You won\'t see their products or messages.',
                    confirmLabel: 'Block',
                    isDestructive: true,
                    onConfirm: () {
                      showThriftSnackBar(context, 'User has been blocked');
                    },
                  );
                },
              ),
              _OptionTile(
                icon: Icons.flag_outlined,
                label: 'Report Seller',
                isDestructive: true,
                onTap: () {
                  Navigator.pop(ctx);
                  context.push('${RouteNames.reportSeller}?seller=$username');
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  void _showConfirmationDialog(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
    required bool isDestructive,
    required VoidCallback onConfirm,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: AppTypography.heading),
        content: Text(message, style: AppTypography.body.copyWith(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: AppTypography.body.copyWith(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              onConfirm();
            },
            child: Text(
              confirmLabel,
              style: AppTypography.body.copyWith(
                color: isDestructive ? AppColors.error : AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Profile Header
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildProfileHeader(
    BuildContext context, {
    required dynamic seller,
    required double rating,
    required int reviews,
    required int sold,
    required int following,
    required int followers,
    required bool isFollowing,
    required DataProvider data,
  }) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Column(
        children: [
          // Avatar
          ThriftAvatar(imageUrl: seller.avatarUrl, size: 80),

          const SizedBox(height: 12),

          // Shop Name & Verification Icon
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                seller.shopName ?? seller.name,
                style: AppTypography.heading.copyWith(fontWeight: FontWeight.w700),
              ),
              if (seller.isVerified) ...[
                const SizedBox(width: 6),
                const Icon(Icons.verified, color: AppColors.primary, size: 20),
              ],
            ],
          ),

          const SizedBox(height: 2),

          // Username
          Text(
            '@${seller.username}',
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),

          const SizedBox(height: 12),

          // Seller Trust Badge & Score
          SellerTrustBadge(
            trustScore: seller.trustScore,
            isVerified: seller.isVerified,
            shopName: seller.shopName ?? seller.name,
          ),

          const SizedBox(height: 16),

          // Stats row
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _StatColumn(
                value: '${rating.toStringAsFixed(1)} ★',
                label: '$reviews reviews',
              ),
              const SizedBox(width: 28),
              _StatColumn(value: '$sold', label: 'sold'),
              const SizedBox(width: 28),
              _StatColumn(value: '$following', label: 'following'),
              const SizedBox(width: 28),
              _StatColumn(value: '$followers', label: 'followers'),
            ],
          ),

          const SizedBox(height: 12),

          // Bio
          if (seller.bio != null && seller.bio!.isNotEmpty)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                    child: Text(
                      seller.bio!,
                      style: AppTypography.body.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),

          const SizedBox(height: 20),

          // Action buttons — Message & Follow
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => context.push('/chat'),
                  icon: const Icon(Icons.chat_bubble_outline, size: 18),
                  label: Text(
                    'Message',
                    style: AppTypography.body.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: AppColors.border, width: 1.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => data.toggleFollow(username),
                  icon: Icon(
                    isFollowing ? Icons.check : Icons.add,
                    size: 18,
                    color: isFollowing ? AppColors.primary : Colors.white,
                  ),
                  label: Text(
                    isFollowing ? 'Following' : 'Follow',
                    style: AppTypography.body.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isFollowing ? AppColors.primary : Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isFollowing
                        ? AppColors.primaryLight
                        : AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: isFollowing
                          ? const BorderSide(color: AppColors.primary, width: 1.5)
                          : BorderSide.none,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Product Grid (3 columns — Instagram gallery style)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildProductGrid(BuildContext context, List<ProductModel> products) {
    if (products.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.textPrimary, width: 2),
              ),
              child: const Icon(Icons.grid_off, size: 48, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 16),
            Text(
              'No products available yet.',
              style: AppTypography.subheading.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 1, // minimal spacing
        crossAxisSpacing: 1, // minimal spacing
        childAspectRatio: 1.0, // perfect square
      ),
      itemCount: products.length,
      itemBuilder: (_, i) => _ShopGridItem(
        product: products[i],
        onTap: () => context.push('/product/${products[i].id}'),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Helper Widgets
// ═════════════════════════════════════════════════════════════════════════════

/// Stat column used in the profile header (e.g. "128 followers").
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
          style: AppTypography.subheading.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: AppTypography.caption.copyWith(
            fontSize: 11,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// Option tile used in the three-dot bottom sheet.
class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDestructive = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        icon,
        color: isDestructive ? AppColors.error : AppColors.textPrimary,
        size: 22,
      ),
      title: Text(
        label,
        style: AppTypography.body.copyWith(
          color: isDestructive ? AppColors.error : AppColors.textPrimary,
          fontWeight: FontWeight.w500,
        ),
      ),
      onTap: onTap,
    );
  }
}

/// Instagram-style grid tile. Perfectly square, minimal spacing, no title/price, just image and status.
class _ShopGridItem extends StatelessWidget {
  const _ShopGridItem({required this.product, required this.onTap});
  final ProductModel product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Product image with Hero animation
          Hero(
            tag: 'product_image_${product.id}',
            child: CachedNetworkImage(
              imageUrl: product.imageUrl,
              fit: BoxFit.cover,
              memCacheWidth: 300,
              placeholder: (_, _) => Container(color: AppColors.surfaceVariant),
              errorWidget: (_, _, _) => Container(
                color: AppColors.surfaceVariant,
                child: const Center(
                  child: Icon(Icons.image_outlined, color: AppColors.textHint, size: 24),
                ),
              ),
            ),
          ),
          
          // Status Overlay
          if (product.status == ProductStatus.sold)
            Positioned(
              bottom: 4,
              right: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('SOLD', style: AppTypography.caption.copyWith(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
              ),
            )
          else if (product.hasActiveBid)
            Positioned(
              bottom: 4,
              right: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('BID', style: AppTypography.caption.copyWith(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
              ),
            ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Sliver App Bar Delegate for Sticky TabBar
// ═════════════════════════════════════════════════════════════════════════════

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverAppBarDelegate(this._tabBar);

  final TabBar _tabBar;

  @override
  double get minExtent => _tabBar.preferredSize.height;
  @override
  double get maxExtent => _tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: AppColors.surface,
      child: _tabBar,
    );
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) {
    return false;
  }
}
