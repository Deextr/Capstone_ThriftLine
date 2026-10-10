import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import '../../../widgets/thrift_widgets.dart';
import '../controllers/following_shops_controller.dart';
import '../data/followed_shop_item.dart';
import '../presentation/widgets/followed_shop_card.dart';

class FollowingShopsScreen extends StatefulWidget {
  const FollowingShopsScreen({super.key});

  @override
  State<FollowingShopsScreen> createState() => _FollowingShopsScreenState();
}

class _FollowingShopsScreenState extends State<FollowingShopsScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<FollowingShopsController>();
    final shops = controller.shops;
    final isLoading = controller.isLoading && shops.isEmpty;
    final hasError = controller.errorMessage != null && shops.isEmpty;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _buildAppBar(context, controller),
      body: SafeArea(
        child: Column(
          children: [
            // Filter chips
            _buildFilterBar(context, controller),

            // Content
            Expanded(
              child: RefreshIndicator(
                color: AppColors.primary,
                onRefresh: controller.refresh,
                child: _buildBody(
                  context,
                  controller,
                  shops,
                  isLoading,
                  hasError,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    FollowingShopsController controller,
  ) {
    final isSearching = controller.isSearching;

    return AppBar(
      backgroundColor: AppColors.surface,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      leading: IconButton(
        icon: Icon(
          Icons.arrow_back_rounded,
          color: AppColors.textPrimary,
        ),
        onPressed: () {
          if (isSearching) {
            controller.toggleSearch(false);
            _searchController.clear();
          } else {
            context.pop();
          }
        },
      ),
      title: isSearching
          ? TextField(
              controller: _searchController,
              autofocus: true,
              style: AppTypography.body,
              decoration: InputDecoration(
                hintText: 'Search followed shops...',
                hintStyle: AppTypography.body.copyWith(
                  color: AppColors.textHint,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
              onChanged: controller.setSearchQuery,
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Following Shops',
                  style: AppTypography.heading.copyWith(fontSize: 18),
                ),
                if (controller.totalCount > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${controller.totalCount}',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.primaryDark,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ],
            ),
      centerTitle: false,
      actions: [
        IconButton(
          icon: Icon(
            isSearching ? Icons.close_rounded : Icons.search_rounded,
            color: AppColors.textPrimary,
          ),
          onPressed: () {
            if (isSearching) {
              controller.toggleSearch(false);
              _searchController.clear();
            } else {
              controller.toggleSearch(true);
            }
          },
        ),
      ],
    );
  }

  Widget _buildFilterBar(
    BuildContext context,
    FollowingShopsController controller,
  ) {
    return Container(
      color: AppColors.surface,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: FollowingFilter.values.map((filter) {
            final isSelected = controller.filter == filter;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(filter.label),
                selected: isSelected,
                onSelected: (_) => controller.setFilter(filter),
                labelStyle: AppTypography.caption.copyWith(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? AppColors.primaryDark
                      : AppColors.textSecondary,
                ),
                backgroundColor: AppColors.surfaceVariant.withValues(
                  alpha: 0.6,
                ),
                selectedColor: AppColors.primaryLight,
                checkmarkColor: AppColors.primaryDark,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color: isSelected
                        ? AppColors.primary.withValues(alpha: 0.5)
                        : Colors.transparent,
                    width: 1,
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    FollowingShopsController controller,
    List<FollowedShopItem> shops,
    bool isLoading,
    bool hasError,
  ) {
    if (isLoading) {
      return const _FollowingShopsSkeleton();
    }

    if (hasError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.wifi_off_rounded,
                  size: 36,
                  color: AppColors.error,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Unable to load followed shops',
                style: AppTypography.subheading.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                controller.errorMessage ?? 'Please check your connection.',
                style: AppTypography.body.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ThriftButton(
                label: 'Try Again',
                expand: false,
                onPressed: controller.refresh,
              ),
            ],
          ),
        ),
      );
    }

    if (shops.isEmpty) {
      return _buildEmptyState(context, controller);
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: shops.length,
      itemBuilder: (context, index) {
        final shop = shops[index];
        return FollowedShopCard(
          shop: shop,
          isFollowing: true,
          onToggleFollow: () => _confirmUnfollow(context, controller, shop),
        );
      },
    );
  }

  Widget _buildEmptyState(
    BuildContext context,
    FollowingShopsController controller,
  ) {
    final isSearching = controller.searchQuery.isNotEmpty;
    final isFiltered = controller.filter != FollowingFilter.all;

    String title;
    String subtitle;
    String? buttonText;
    VoidCallback? onButtonTap;

    if (isSearching) {
      title = 'No shops found';
      subtitle = 'No followed shops match "${controller.searchQuery}".';
      buttonText = 'Clear Search';
      onButtonTap = () {
        controller.setSearchQuery('');
        _searchController.clear();
      };
    } else if (isFiltered) {
      title = 'No matching shops';
      subtitle = 'None of your followed shops match this category filter.';
      buttonText = 'Show All';
      onButtonTap = () => controller.setFilter(FollowingFilter.all);
    } else {
      title = 'No Followed Shops';
      subtitle = 'You are not following any shops yet.';
      buttonText = null;
      onButtonTap = null;
    }

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.storefront_outlined,
                      size: 44,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    title,
                    style: AppTypography.heading.copyWith(fontSize: 18),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    style: AppTypography.body.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (buttonText != null && onButtonTap != null) ...[
                    const SizedBox(height: 24),
                    ThriftButton(
                      label: buttonText,
                      expand: false,
                      onPressed: onButtonTap,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _confirmUnfollow(
    BuildContext context,
    FollowingShopsController controller,
    FollowedShopItem shop,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                ThriftAvatar(
                  imageUrl: shop.avatarUrl,
                  name: shop.shopName,
                  size: 60,
                ),
                const SizedBox(height: 12),
                Text(
                  'Unfollow ${shop.shopName}?',
                  style: AppTypography.heading.copyWith(fontSize: 18),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'You will no longer see updates from @${shop.username} on your feed.',
                  style: AppTypography.body.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          side: BorderSide(color: AppColors.border),
                        ),
                        child: Text(
                          'Cancel',
                          style: AppTypography.body.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          Navigator.pop(ctx);
                          await controller.toggleFollow(shop.sellerId);
                          if (!context.mounted) return;
                          showThriftSnackBar(
                            context,
                            'Unfollowed ${shop.shopName}',
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.error,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Unfollow',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FollowingShopsSkeleton extends StatelessWidget {
  const _FollowingShopsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 3,
      itemBuilder: (_, _) => Shimmer.fromColors(
        baseColor: Colors.grey.shade200,
        highlightColor: Colors.grey.shade50,
        child: Container(
          margin: const EdgeInsets.only(bottom: 16),
          height: 180,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
    );
  }
}
