import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../core/constants/app_colors.dart';
import '../core/constants/app_constants.dart';
import 'product_card.dart';
import 'thrift_widgets.dart';

/// Shared shimmer colors for ThriftLine skeleton placeholders.
Color get _shimmerBase => AppColors.border;
Color get _shimmerHighlight => AppColors.surface;

/// Wraps [child] with a single shimmer animation (prefer for lists/grids).
class ThriftShimmer extends StatelessWidget {
  const ThriftShimmer({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: _shimmerBase,
      highlightColor: _shimmerHighlight,
      child: child,
    );
  }
}

/// Neutral placeholder block; pair with [ThriftShimmer] for animated lists.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.width, this.height = 16, this.radius = 8});

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: _shimmerBase,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Standalone shimmering box (backward compatible with admin/home inline usage).
class ShimmerBox extends StatelessWidget {
  const ShimmerBox({super.key, this.width, this.height = 16, this.radius = 8});

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return ThriftShimmer(
      child: SkeletonBox(width: width, height: height, radius: radius),
    );
  }
}

class SkeletonCircle extends StatelessWidget {
  const SkeletonCircle({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SkeletonBox(width: size, height: size, radius: size / 2);
  }
}

/// Compact grid/rail product placeholder matching [ProductCard] dimensions.
class ProductCardSkeleton extends StatelessWidget {
  const ProductCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.4)),
      ),
      clipBehavior: Clip.antiAlias,
      child: const SkeletonBox(
        width: double.infinity,
        height: double.infinity,
        radius: 0,
      ),
    );
  }
}

class SearchResultsGridSkeleton extends StatelessWidget {
  const SearchResultsGridSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    return ThriftShimmer(
      child: GridView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 8,
        gridDelegate: ProductCard.gridDelegateFor(
          maxWidth: MediaQuery.sizeOf(context).width,
          compact: true,
          textScale: textScale,
        ),
        itemBuilder: (_, _) => const ProductCardSkeleton(),
      ),
    );
  }
}

class ProductGridSkeleton extends StatelessWidget {
  const ProductGridSkeleton({
    super.key,
    this.itemCount = 6,
    this.padding = const EdgeInsets.all(16),
  });

  final int itemCount;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    return ThriftShimmer(
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: padding,
        itemCount: itemCount,
        gridDelegate: ProductCard.gridDelegateFor(
          maxWidth: MediaQuery.sizeOf(context).width,
          compact: true,
          textScale: textScale,
        ),
        itemBuilder: (_, _) => const ProductCardSkeleton(),
      ),
    );
  }
}

class ProductRailSkeleton extends StatelessWidget {
  const ProductRailSkeleton({super.key, this.itemCount = 3});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    final cardW = ProductCard.cardWidthFor(MediaQuery.sizeOf(context).width);
    final height = ProductCard.cardHeightFor(cardW);
    return ThriftShimmer(
      child: SizedBox(
        height: height,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: itemCount,
          separatorBuilder: (_, _) =>
              const SizedBox(width: ProductCard.gridSpacing),
          itemBuilder: (_, _) => SizedBox(
            width: cardW,
            height: height,
            child: const ProductCardSkeleton(),
          ),
        ),
      ),
    );
  }
}

/// Scrollable product grid for full-screen favorites/search loading.
class ProductGridSkeletonScroll extends StatelessWidget {
  const ProductGridSkeletonScroll({super.key, this.itemCount = 8});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    return ThriftShimmer(
      child: GridView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: itemCount,
        gridDelegate: ProductCard.gridDelegateFor(
          maxWidth: MediaQuery.sizeOf(context).width,
          compact: true,
          textScale: textScale,
        ),
        itemBuilder: (_, _) => const ProductCardSkeleton(),
      ),
    );
  }
}

/// Horizontal listing row: thumbnail + title/price/chips (bids, seller listings).
class ListingRowSkeleton extends StatelessWidget {
  const ListingRowSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ThriftCard(
      child: const Row(
        children: [
          SkeletonBox(width: 72, height: 72, radius: 8),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: double.infinity, height: 16),
                SizedBox(height: 8),
                SkeletonBox(width: 100, height: 14),
                SizedBox(height: 12),
                SkeletonBox(width: 140, height: 14),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ListingListSkeleton extends StatelessWidget {
  const ListingListSkeleton({super.key, this.itemCount = 4});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return ThriftShimmer(
      child: ListView.separated(
        padding: const EdgeInsets.all(AppConstants.spacingMd),
        itemCount: itemCount,
        separatorBuilder: (_, _) =>
            const SizedBox(height: AppConstants.spacingMd),
        itemBuilder: (_, _) => const ListingRowSkeleton(),
      ),
    );
  }
}

class ConversationRowSkeleton extends StatelessWidget {
  const ConversationRowSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonCircle(size: 48),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 140, height: 16),
                SizedBox(height: 8),
                SkeletonBox(width: double.infinity, height: 13),
                SizedBox(height: 6),
                SkeletonBox(width: 200, height: 13),
              ],
            ),
          ),
          SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              SkeletonBox(width: 36, height: 12),
              SizedBox(height: 8),
              SkeletonCircle(size: 10),
            ],
          ),
        ],
      ),
    );
  }
}

class ConversationListSkeleton extends StatelessWidget {
  const ConversationListSkeleton({super.key, this.itemCount = 8});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return ThriftShimmer(
      child: ListView.separated(
        padding: const EdgeInsets.only(bottom: 96),
        itemCount: itemCount,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, _) => const ConversationRowSkeleton(),
      ),
    );
  }
}

class NotificationRowSkeleton extends StatelessWidget {
  const NotificationRowSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const ListTile(
      leading: SkeletonCircle(size: 40),
      title: SkeletonBox(width: 180, height: 14),
      subtitle: Padding(
        padding: EdgeInsets.only(top: 8),
        child: SkeletonBox(width: double.infinity, height: 12),
      ),
    );
  }
}

class NotificationListSkeleton extends StatelessWidget {
  const NotificationListSkeleton({super.key, this.itemCount = 10});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return ThriftShimmer(
      child: ListView.builder(
        itemCount: itemCount,
        itemBuilder: (_, _) => const NotificationRowSkeleton(),
      ),
    );
  }
}

class OrderListTileSkeleton extends StatelessWidget {
  const OrderListTileSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const ListTile(
      leading: SkeletonBox(width: 48, height: 48, radius: 8),
      title: SkeletonBox(width: double.infinity, height: 16),
      subtitle: Padding(
        padding: EdgeInsets.only(top: 8),
        child: SkeletonBox(width: 120, height: 13),
      ),
      trailing: SkeletonBox(width: 64, height: 14),
    );
  }
}

class OrderListSkeleton extends StatelessWidget {
  const OrderListSkeleton({super.key, this.itemCount = 6});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return ThriftShimmer(
      child: ListView.builder(
        itemCount: itemCount,
        itemBuilder: (_, _) => const OrderListTileSkeleton(),
      ),
    );
  }
}

class TrackOrderCardSkeleton extends StatelessWidget {
  const TrackOrderCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ThriftCard(
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 56, height: 56, radius: 8),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(width: double.infinity, height: 16),
                    SizedBox(height: 8),
                    SkeletonBox(width: 100, height: 12),
                  ],
                ),
              ),
            ],
          ),
          Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonCircle(size: 10),
              SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(width: 120, height: 14),
                    SizedBox(height: 6),
                    SkeletonBox(width: double.infinity, height: 12),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: SkeletonBox(width: 100, height: 14),
          ),
        ],
      ),
    );
  }
}

class TrackOrdersListSkeleton extends StatelessWidget {
  const TrackOrdersListSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ThriftShimmer(
      child: ListView.separated(
        padding: const EdgeInsets.all(AppConstants.spacingMd),
        itemCount: 4,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, i) {
          if (i == 0) {
            return const SkeletonBox(width: 160, height: 22, radius: 6);
          }
          return const TrackOrderCardSkeleton();
        },
      ),
    );
  }
}

class SellerOrderCardSkeleton extends StatelessWidget {
  const SellerOrderCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ThriftCard(
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: SkeletonBox(width: double.infinity, height: 12)),
              SizedBox(width: 8),
              SkeletonBox(width: 72, height: 22, radius: 20),
            ],
          ),
          SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 56, height: 56, radius: 8),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(width: double.infinity, height: 16),
                    SizedBox(height: 6),
                    SkeletonBox(width: 90, height: 13),
                    SizedBox(height: 6),
                    SkeletonBox(width: 120, height: 13),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class SellerOrdersListSkeleton extends StatelessWidget {
  const SellerOrdersListSkeleton({super.key, this.itemCount = 3});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return ThriftShimmer(
      child: ListView.separated(
        padding: const EdgeInsets.all(AppConstants.spacingMd),
        itemCount: itemCount,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, _) => const SellerOrderCardSkeleton(),
      ),
    );
  }
}

class CartItemRowSkeleton extends StatelessWidget {
  const CartItemRowSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          SkeletonBox(width: 20, height: 20, radius: 4),
          SizedBox(width: 8),
          SkeletonBox(width: 72, height: 72, radius: 10),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: double.infinity, height: 14),
                SizedBox(height: 8),
                SkeletonBox(width: 80, height: 14),
                SizedBox(height: 10),
                SkeletonBox(width: 100, height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CartScreenSkeleton extends StatelessWidget {
  const CartScreenSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ThriftShimmer(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: AppColors.border.withValues(alpha: 0.6),
              ),
            ),
            child: const Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(12, 12, 12, 4),
                  child: Row(
                    children: [
                      SkeletonBox(width: 20, height: 20, radius: 4),
                      SizedBox(width: 8),
                      SkeletonBox(width: 140, height: 16),
                    ],
                  ),
                ),
                CartItemRowSkeleton(),
                CartItemRowSkeleton(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CheckoutScreenSkeleton extends StatelessWidget {
  const CheckoutScreenSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const CartScreenSkeleton();
  }
}

class LookingForCardSkeleton extends StatelessWidget {
  const LookingForCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SkeletonCircle(size: 44),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(width: 120, height: 14),
                    SizedBox(height: 6),
                    SkeletonBox(width: 80, height: 12),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 14),
          SkeletonBox(width: double.infinity, height: 16),
          SizedBox(height: 8),
          SkeletonBox(width: double.infinity, height: 14),
          SizedBox(height: 8),
          SkeletonBox(width: 200, height: 14),
          SizedBox(height: 14),
          SkeletonBox(width: 100, height: 28, radius: 20),
        ],
      ),
    );
  }
}

class LookingForListSkeleton extends StatelessWidget {
  const LookingForListSkeleton({super.key, this.itemCount = 4});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return ThriftShimmer(
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: itemCount,
        itemBuilder: (_, _) => const LookingForCardSkeleton(),
      ),
    );
  }
}

class ProductDetailSkeleton extends StatelessWidget {
  const ProductDetailSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final imageHeight = width / ProductCard.imageAspectRatio;
    return ThriftShimmer(
      child: SingleChildScrollView(
        physics: AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBox(width: width, height: imageHeight, radius: 0),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(width: 100, height: 22),
                    SizedBox(height: 10),
                    SkeletonBox(width: 160, height: 14),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 80, height: 14),
                  SizedBox(height: 8),
                  SkeletonBox(width: double.infinity, height: 24),
                  SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: SkeletonBox(height: 48, radius: 10)),
                      SizedBox(width: 8),
                      Expanded(child: SkeletonBox(height: 48, radius: 10)),
                    ],
                  ),
                  SizedBox(height: 20),
                  SkeletonBox(width: double.infinity, height: 14),
                  SizedBox(height: 8),
                  SkeletonBox(width: double.infinity, height: 14),
                  SizedBox(height: 8),
                  SkeletonBox(width: 240, height: 14),
                ],
              ),
            ),
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }
}

class SellerPublicProfileSkeleton extends StatelessWidget {
  const SellerPublicProfileSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ThriftShimmer(
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                children: [
                  const SkeletonCircle(size: 88),
                  const SizedBox(height: 12),
                  SkeletonBox(width: 160, height: 20),
                  const SizedBox(height: 8),
                  const SkeletonBox(width: 100, height: 14),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      for (var i = 0; i < 3; i++) ...[
                        if (i > 0) const SizedBox(width: 12),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: const Column(
                              children: [
                                SkeletonBox(width: 40, height: 18),
                                SizedBox(height: 6),
                                SkeletonBox(width: 56, height: 12),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverToBoxAdapter(
              child: ProductGridSkeleton(itemCount: 4),
            ),
          ),
        ],
      ),
    );
  }
}

class ChatThreadSkeleton extends StatelessWidget {
  const ChatThreadSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ThriftShimmer(
      child: ListView(
        reverse: true,
        padding: const EdgeInsets.all(16),
        children: const [
          Align(
            alignment: Alignment.centerRight,
            child: SkeletonBox(width: 180, height: 40, radius: 18),
          ),
          SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: SkeletonBox(width: 220, height: 48, radius: 18),
          ),
          SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: SkeletonBox(width: 140, height: 36, radius: 18),
          ),
          SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: SkeletonBox(width: 260, height: 56, radius: 18),
          ),
        ],
      ),
    );
  }
}

class AddressCardSkeleton extends StatelessWidget {
  const AddressCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ThriftCard(
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(width: 120, height: 16),
          SizedBox(height: 10),
          SkeletonBox(width: double.infinity, height: 14),
          SizedBox(height: 6),
          SkeletonBox(width: 200, height: 14),
          SizedBox(height: 12),
          SkeletonBox(width: 140, height: 12),
        ],
      ),
    );
  }
}

class AddressListSkeleton extends StatelessWidget {
  const AddressListSkeleton({super.key, this.itemCount = 3});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return ThriftShimmer(
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: itemCount,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, _) => const AddressCardSkeleton(),
      ),
    );
  }
}

class ProfileFormSkeleton extends StatelessWidget {
  const ProfileFormSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ThriftShimmer(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.spacingMd,
          vertical: 24,
        ),
        child: Column(
          children: [
            const SkeletonCircle(size: 90),
            const SizedBox(height: 32),
            for (var i = 0; i < 4; i++) ...[
              const Align(
                alignment: Alignment.centerLeft,
                child: SkeletonBox(width: 80, height: 12),
              ),
              const SizedBox(height: 8),
              const SkeletonBox(width: double.infinity, height: 48, radius: 12),
              const SizedBox(height: 16),
            ],
            const SkeletonBox(width: double.infinity, height: 48, radius: 12),
          ],
        ),
      ),
    );
  }
}

class ReportRowSkeleton extends StatelessWidget {
  const ReportRowSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ThriftCard(
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(width: 140, height: 16),
          SizedBox(height: 8),
          SkeletonBox(width: double.infinity, height: 14),
          SizedBox(height: 8),
          SkeletonBox(width: 100, height: 12),
        ],
      ),
    );
  }
}

class ReportListSkeleton extends StatelessWidget {
  const ReportListSkeleton({super.key, this.itemCount = 5});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return ThriftShimmer(
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: itemCount,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, _) => const ReportRowSkeleton(),
      ),
    );
  }
}

class ReportDetailSkeleton extends StatelessWidget {
  const ReportDetailSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ThriftShimmer(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: const [
          SkeletonBox(width: 200, height: 24),
          SizedBox(height: 12),
          SkeletonBox(width: 140, height: 14),
          SizedBox(height: 20),
          SkeletonBox(width: double.infinity, height: 120, radius: 12),
          SizedBox(height: 16),
          SkeletonBox(width: double.infinity, height: 14),
          SizedBox(height: 8),
          SkeletonBox(width: double.infinity, height: 14),
        ],
      ),
    );
  }
}

class PaymentMethodSkeleton extends StatelessWidget {
  const PaymentMethodSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ThriftShimmer(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBox(width: 120, height: 18),
            SizedBox(height: 12),
            SkeletonBox(width: double.infinity, height: 14),
            SizedBox(height: 8),
            SkeletonBox(width: 180, height: 14),
          ],
        ),
      ),
    );
  }
}

class OrderConfirmationSkeleton extends StatelessWidget {
  const OrderConfirmationSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ThriftShimmer(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppConstants.spacingLg),
        child: Column(
          children: [
            const SkeletonCircle(size: 72),
            const SizedBox(height: 20),
            const SkeletonBox(width: 220, height: 22),
            const SizedBox(height: 12),
            const SkeletonBox(width: double.infinity, height: 14),
            const SizedBox(height: 24),
            ThriftCard(
              child: Column(
                children: List.generate(
                  3,
                  (_) => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        SkeletonBox(width: 48, height: 48, radius: 8),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SkeletonBox(width: double.infinity, height: 14),
                              SizedBox(height: 6),
                              SkeletonBox(width: 80, height: 12),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SellerDashboardSectionSkeleton extends StatelessWidget {
  const SellerDashboardSectionSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const ThriftShimmer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: 10),
          SellerOrderCardSkeleton(),
          SizedBox(height: 10),
          SellerOrderCardSkeleton(),
        ],
      ),
    );
  }
}

class BuyNowSkeleton extends StatelessWidget {
  const BuyNowSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const SkeletonBox(width: 24, height: 24, radius: 4),
        title: const SkeletonBox(width: 100, height: 18),
      ),
      body: ThriftShimmer(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: const [
            Row(
              children: [
                SkeletonBox(width: 88, height: 88, radius: 10),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(width: double.infinity, height: 16),
                      SizedBox(height: 8),
                      SkeletonBox(width: 80, height: 18),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 24),
            SkeletonBox(width: double.infinity, height: 48, radius: 12),
            SizedBox(height: 16),
            SkeletonBox(width: double.infinity, height: 120, radius: 12),
          ],
        ),
      ),
    );
  }
}

class OrderDetailSkeleton extends StatelessWidget {
  const OrderDetailSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ThriftShimmer(
      child: ListView(
        padding: const EdgeInsets.all(AppConstants.spacingMd),
        children: const [
          SkeletonBox(width: 140, height: 14),
          SizedBox(height: 16),
          TrackOrderCardSkeleton(),
          SizedBox(height: 16),
          SkeletonBox(width: double.infinity, height: 160, radius: 12),
          SizedBox(height: 12),
          SkeletonBox(width: double.infinity, height: 48, radius: 12),
        ],
      ),
    );
  }
}

class ReportFormSkeleton extends StatelessWidget {
  const ReportFormSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ThriftShimmer(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: const [
          SkeletonBox(width: 220, height: 22),
          SizedBox(height: 8),
          SkeletonBox(width: double.infinity, height: 14),
          SizedBox(height: 24),
          SkeletonBox(width: 100, height: 12),
          SizedBox(height: 8),
          SkeletonBox(width: double.infinity, height: 48, radius: 12),
          SizedBox(height: 16),
          SkeletonBox(width: 120, height: 12),
          SizedBox(height: 8),
          SkeletonBox(width: double.infinity, height: 120, radius: 12),
        ],
      ),
    );
  }
}

class ReviewFormSkeleton extends StatelessWidget {
  const ReviewFormSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ThriftShimmer(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: const [
          SkeletonBox(width: 200, height: 22),
          SizedBox(height: 12),
          Row(
            children: [
              SkeletonBox(width: 56, height: 56, radius: 8),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(width: double.infinity, height: 16),
                    SizedBox(height: 6),
                    SkeletonBox(width: 100, height: 13),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 24),
          SkeletonBox(width: 160, height: 28),
          SizedBox(height: 16),
          SkeletonBox(width: double.infinity, height: 120, radius: 12),
        ],
      ),
    );
  }
}

class VerifiedSellerGridSkeleton extends StatelessWidget {
  const VerifiedSellerGridSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ThriftShimmer(
      child: GridView.builder(
        shrinkWrap: true,
        physics: NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: 4,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.1,
        ),
        itemBuilder: (_, _) => Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          padding: const EdgeInsets.all(12),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SkeletonCircle(size: 48),
              SizedBox(height: 10),
              SkeletonBox(width: 100, height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
