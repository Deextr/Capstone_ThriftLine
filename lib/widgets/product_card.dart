import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_colors.dart';
import '../core/constants/app_constants.dart';
import '../core/constants/app_typography.dart';
import '../core/utils/cart_popularity.dart';
import '../core/utils/formatters.dart';
import '../models/enums.dart';
import '../models/product_model.dart';
import '../providers/saved_items_provider.dart';
import 'countdown_timer.dart';

enum ProductCardVariant { grid, list }

/// Image-first marketplace card. Hierarchy: image → name → price.
class ProductCard extends StatefulWidget {
  const ProductCard({
    super.key,
    required this.product,
    this.variant = ProductCardVariant.grid,
    this.onTap,
    this.showCountdown = false,
    this.compact = false,
    this.cartAddCount,
  });

  final ProductModel product;
  final ProductCardVariant variant;
  final VoidCallback? onTap;
  final bool showCountdown;
  final bool compact;
  final int? cartAddCount;

  static const imageAspectRatio = 4 / 5;
  static const gridSpacing = 12.0;
  static const gridHorizontalPadding = 32.0;

  static double footerHeight({bool compact = true, double textScale = 1}) {
    return 0;
  }

  static int crossAxisCountFor(double maxWidth) {
    return maxWidth >= AppConstants.breakpointTablet ? 3 : 2;
  }

  static double cardWidthFor(
    double maxWidth, {
    double horizontalPadding = gridHorizontalPadding,
  }) {
    final count = crossAxisCountFor(maxWidth);
    final available = (maxWidth - horizontalPadding).clamp(200.0, 2000.0);
    return (available - gridSpacing * (count - 1)) / count;
  }

  static double cardHeightFor(double cardWidth) => cardWidth / imageAspectRatio;

  static double gridChildAspectRatio({
    required double cardWidth,
    bool compact = true,
    double textScale = 1,
  }) {
    return imageAspectRatio;
  }

  static SliverGridDelegate gridDelegateFor({
    required double maxWidth,
    double horizontalPadding = gridHorizontalPadding,
    double spacing = gridSpacing,
    bool compact = true,
    double textScale = 1,
  }) {
    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: crossAxisCountFor(maxWidth),
      mainAxisSpacing: spacing,
      crossAxisSpacing: spacing,
      childAspectRatio: imageAspectRatio,
    );
  }

  @override
  State<ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<ProductCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _heartController;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _heartController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void dispose() {
    _heartController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.variant == ProductCardVariant.grid
        ? _buildGrid(context)
        : _buildList(context);
  }

  Widget _buildGrid(BuildContext context) {
    final savedItems = context.watch<SavedItemsProvider>();
    final saved = savedItems.isSaved(widget.product.id);
    final compact = widget.compact;
    final isLiveAuction = widget.product.hasActiveBid;
    final popularity = !isLiveAuction
        ? formatCartPopularity(widget.cartAddCount ?? 0)
        : null;
    final showTimer =
        widget.showCountdown &&
        isLiveAuction &&
        widget.product.bidEndTime != null;

    return AnimatedScale(
      scale: _isPressed ? 0.97 : 1.0,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: Material(
        color: AppColors.surface,
        elevation: 0,
        shadowColor: Colors.black.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        child: InkWell(
          onTap: widget.onTap,
          onHighlightChanged: (v) => setState(() => _isPressed = v),
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          child: Ink(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              child: AspectRatio(
                aspectRatio: ProductCard.imageAspectRatio,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(
                      imageUrl: widget.product.imageUrl,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      memCacheWidth: 480,
                      fadeInDuration: const Duration(milliseconds: 180),
                      placeholder: (_, _) => const _ImagePlaceholder(),
                      errorWidget: (_, _, _) => const _ImageFallback(),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: 96,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.55),
                                Colors.black.withValues(alpha: 0.82),
                              ],
                              stops: const [0.0, 0.48, 1.0],
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (isLiveAuction)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _AuctionListingBadge(),
                            if (showTimer) ...[
                              const SizedBox(height: 6),
                              _CountdownPill(
                                endTime: widget.product.bidEndTime!,
                              ),
                            ],
                          ],
                        ),
                      ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (popularity != null) ...[
                            _CartPopularityBadge(label: popularity),
                            const SizedBox(width: 6),
                          ],
                          _SaveButton(
                            saved: saved,
                            controller: _heartController,
                            onTap: () {
                              _heartController.forward(from: 0);
                              savedItems.toggleSave(
                                widget.product.id,
                                widget.product,
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      left: 10,
                      right: 10,
                      bottom: 10,
                      child: _ImageCaption(
                        product: widget.product,
                        compact: compact,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    final savedItems = context.watch<SavedItemsProvider>();
    final saved = savedItems.isSaved(widget.product.id);

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        child: Ink(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
          ),
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                child: CachedNetworkImage(
                  imageUrl: widget.product.imageUrl,
                  width: 88,
                  height: 88,
                  fit: BoxFit.cover,
                  memCacheWidth: 240,
                  placeholder: (_, _) => const SizedBox(
                    width: 88,
                    height: 88,
                    child: _ImagePlaceholder(),
                  ),
                  errorWidget: (_, _, _) => const SizedBox(
                    width: 88,
                    height: 88,
                    child: _ImageFallback(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.product.title,
                      style: AppTypography.body.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    _PriceLine(product: widget.product, compact: false),
                  ],
                ),
              ),
              IconButton(
                onPressed: () {
                  _heartController.forward(from: 0);
                  savedItems.toggleSave(widget.product.id, widget.product);
                },
                icon: Icon(
                  saved
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: saved ? AppColors.error : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImageCaption extends StatelessWidget {
  const _ImageCaption({required this.product, required this.compact});

  final ProductModel product;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final isAuction = product.sellingType == SellingType.auction;
    const shadow = [
      Shadow(color: Color(0x99000000), blurRadius: 8, offset: Offset(0, 1)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          product.title,
          style: AppTypography.body.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: compact ? 14 : 15,
            height: 1.2,
            shadows: shadow,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 3),
        if (isAuction)
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: 'Current Bid  ',
                  style: AppTypography.caption.copyWith(
                    color: const Color(0xFFCCFBF1),
                    fontWeight: FontWeight.w700,
                    fontSize: compact ? 12 : 13,
                    shadows: shadow,
                  ),
                ),
                TextSpan(
                  text: formatCurrency(product.displayPrice),
                  style: AppTypography.subheading.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: compact ? 17 : 18,
                    letterSpacing: -0.3,
                    height: 1.1,
                    shadows: shadow,
                  ),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          )
        else
          Text(
            formatCurrency(product.displayPrice),
            style: AppTypography.subheading.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: compact ? 17 : 18,
              letterSpacing: -0.3,
              height: 1.1,
              shadows: shadow,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }
}

class _PriceLine extends StatelessWidget {
  const _PriceLine({required this.product, required this.compact});

  final ProductModel product;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final isAuction = product.sellingType == SellingType.auction;
    final priceStyle = AppTypography.subheading.copyWith(
      color: AppColors.primary,
      fontSize: compact ? 14 : 15,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.3,
      height: 1.15,
    );
    if (!isAuction) {
      return Text(
        formatCurrency(product.displayPrice),
        style: priceStyle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: 'Current Bid ',
            style: AppTypography.caption.copyWith(
              fontSize: compact ? 10.5 : 11,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          TextSpan(
            text: formatCurrency(product.displayPrice),
            style: priceStyle,
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.surfaceVariant,
      child: Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.primary.withValues(alpha: 0.45),
          ),
        ),
      ),
    );
  }
}

class _ImageFallback extends StatelessWidget {
  const _ImageFallback();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.primaryLight.withValues(alpha: 0.55),
      child: Center(
        child: Icon(
          Icons.image_not_supported_outlined,
          color: AppColors.textHint.withValues(alpha: 0.7),
          size: 28,
        ),
      ),
    );
  }
}

class _CartPopularityBadge extends StatelessWidget {
  const _CartPopularityBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label in carts',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 6,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.shopping_bag_outlined,
              size: 12,
              color: AppColors.textPrimary,
            ),
            const SizedBox(width: 3),
            Text(
              label,
              style: AppTypography.caption.copyWith(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AuctionListingBadge extends StatelessWidget {
  const _AuctionListingBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.gavel_rounded, size: 13, color: AppColors.primaryLight),
          const SizedBox(width: 4),
          Text(
            'Bidding',
            style: AppTypography.caption.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _CountdownPill extends StatelessWidget {
  const _CountdownPill({required this.endTime});
  final DateTime endTime;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.schedule_rounded, color: Colors.white, size: 13),
          const SizedBox(width: 4),
          CountdownTimer(
            endTime: endTime,
            format: formatReadableCountdown,
            style: AppTypography.caption.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 12,
              letterSpacing: 0.15,
            ),
          ),
        ],
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  const _SaveButton({
    required this.saved,
    required this.onTap,
    required this.controller,
  });
  final bool saved;
  final VoidCallback onTap;
  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.95),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 32,
          height: 32,
          child: Center(
            child: AnimatedBuilder(
              animation: controller,
              builder: (_, _) => Icon(
                saved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: saved ? AppColors.error : AppColors.textSecondary,
                size: 16,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
