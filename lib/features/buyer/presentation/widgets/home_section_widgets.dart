import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../models/product_model.dart';
import '../../../../widgets/product_card.dart';
import '../../data/home_feed_query.dart';

class HomeSectionHeader extends StatelessWidget {
  const HomeSectionHeader({
    super.key,
    required this.title,
    this.onSeeAll,
    this.topPadding = 28,
  });

  final String title;
  final VoidCallback? onSeeAll;
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, topPadding, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: AppTypography.heading.copyWith(fontSize: 18),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (onSeeAll != null)
            TextButton(
              onPressed: onSeeAll,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: Text(
                'See All',
                style: AppTypography.label.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class HomeSectionStatus<T> extends StatelessWidget {
  const HomeSectionStatus({
    super.key,
    required this.section,
    required this.emptyMessage,
    required this.onRetry,
    this.child,
    this.shimmer,
  });

  final HomeFeedSection<T> section;
  final String emptyMessage;
  final VoidCallback onRetry;
  final Widget? child;
  final Widget? shimmer;

  @override
  Widget build(BuildContext context) {
    if (section.isLoading && section.items.isEmpty) {
      return shimmer ?? const HomeRailShimmer();
    }
    if (section.hasError && section.items.isEmpty) {
      return HomeInlineError(message: section.errorMessage!, onRetry: onRetry);
    }
    if (section.isEmpty) {
      return HomeInlineEmpty(message: emptyMessage);
    }
    return child ?? const SizedBox.shrink();
  }
}

class HomeInlineEmpty extends StatelessWidget {
  const HomeInlineEmpty({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Text(
        message,
        style: AppTypography.body.copyWith(
          color: AppColors.textSecondary,
          fontSize: 13.5,
          height: 1.4,
        ),
      ),
    );
  }
}

class HomeInlineError extends StatelessWidget {
  const HomeInlineError({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message,
              style: AppTypography.body.copyWith(
                color: AppColors.textSecondary,
                fontSize: 13.5,
              ),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class HomeOfflineBanner extends StatelessWidget {
  const HomeOfflineBanner({super.key, required this.cached});
  final bool cached;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        cached
            ? 'You are offline. Showing saved listings.'
            : 'You are offline. Connect to refresh listings.',
        style: AppTypography.caption.copyWith(
          color: const Color(0xFF92400E),
          fontWeight: FontWeight.w600,
          fontSize: 12.5,
        ),
      ),
    );
  }
}

class HomeProductRail extends StatelessWidget {
  const HomeProductRail({
    super.key,
    required this.products,
    required this.cartCounts,
    this.showCountdown = false,
  });

  final List<ProductModel> products;
  final Map<String, int> cartCounts;
  final bool showCountdown;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenW = MediaQuery.sizeOf(context).width;
        final cardW = ProductCard.cardWidthFor(screenW);
        final height = ProductCard.cardHeightFor(cardW);
        return SizedBox(
          height: height,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: products.length,
            separatorBuilder: (_, _) =>
                const SizedBox(width: ProductCard.gridSpacing),
            itemBuilder: (_, i) {
              final p = products[i];
              return SizedBox(
                width: cardW,
                height: height,
                child: ProductCard(
                  product: p,
                  compact: true,
                  showCountdown: showCountdown,
                  cartAddCount: cartCounts[p.id],
                  onTap: () => contextPushProduct(context, p),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

void contextPushProduct(BuildContext context, ProductModel p) {
  context.push('/product/${p.id}');
}

class HomeRailShimmer extends StatelessWidget {
  const HomeRailShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    final cardW = ProductCard.cardWidthFor(MediaQuery.sizeOf(context).width);
    final height = ProductCard.cardHeightFor(cardW);
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: 3,
        separatorBuilder: (_, _) =>
            const SizedBox(width: ProductCard.gridSpacing),
        itemBuilder: (_, _) =>
            SizedBox(width: cardW, height: height, child: const _ShimmerCard()),
      ),
    );
  }
}

class HomeGridShimmer extends StatelessWidget {
  const HomeGridShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 4,
        gridDelegate: ProductCard.gridDelegateFor(
          maxWidth: MediaQuery.sizeOf(context).width,
          compact: true,
          textScale: MediaQuery.textScalerOf(context).scale(1),
        ),
        itemBuilder: (_, _) => const _ShimmerCard(),
      ),
    );
  }
}

class _ShimmerCard extends StatelessWidget {
  const _ShimmerCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.4)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ColoredBox(color: AppColors.surfaceVariant),
      ),
    );
  }
}
