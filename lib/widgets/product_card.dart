import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_colors.dart';
import '../core/constants/app_constants.dart';
import '../core/constants/app_typography.dart';
import '../core/utils/formatters.dart';
import '../models/product_model.dart';
import '../providers/data_provider.dart';
import 'countdown_timer.dart';
import 'thrift_widgets.dart';

enum ProductCardVariant { grid, list }

class ProductCard extends StatefulWidget {
  const ProductCard({
    super.key,
    required this.product,
    this.variant = ProductCardVariant.grid,
    this.onTap,
    this.showCountdown = false,
    this.compact = false,
  });

  final ProductModel product;
  final ProductCardVariant variant;
  final VoidCallback? onTap;
  final bool showCountdown;
  final bool compact;

  @override
  State<ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<ProductCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _heartController;

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
    final data = context.watch<DataProvider>();
    final saved = data.isSaved(widget.product.id);
    final imageHeight = widget.compact ? 116.0 : 150.0;
    final contentPadding = widget.compact
        ? const EdgeInsets.all(8)
        : const EdgeInsets.all(10);

    return ThriftCard(
      onTap: widget.onTap,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
                child: CachedNetworkImage(
                  imageUrl: widget.product.imageUrl,
                  width: double.infinity,
                  height: imageHeight,
                  fit: BoxFit.cover,
                  placeholder: (_, _) => Container(
                    color: AppColors.primaryLight,
                    height: imageHeight,
                  ),
                ),
              ),
              if (widget.product.hasActiveBid)
                Positioned(
                  top: 8,
                  left: 8,
                  child: ThriftBadge(
                    label:
                        widget.showCountdown &&
                            widget.product.bidEndTime != null
                        ? 'Bid ${formatCurrency(widget.product.currentBid ?? 0)}'
                        : 'Bid',
                    variant: BadgeVariant.secondary,
                  ),
                ),
              if (widget.showCountdown && widget.product.bidEndTime != null)
                Positioned(
                  top: 8,
                  right: 40,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.secondary.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: CountdownTimer(
                      endTime: widget.product.bidEndTime!,
                      style: AppTypography.caption.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              Positioned(
                top: 4,
                right: 4,
                child: IconButton(
                  icon: AnimatedBuilder(
                    animation: _heartController,
                    builder: (_, _) => Icon(
                      saved ? Icons.favorite : Icons.favorite_border,
                      color: saved ? AppColors.error : Colors.white,
                      size: 22,
                    ),
                  ),
                  onPressed: () {
                    _heartController.forward(from: 0);
                    data.toggleSave(widget.product.id);
                  },
                ),
              ),
            ],
          ),
          Padding(
            padding: contentPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ThriftAvatar(
                      imageUrl: widget.product.sellerAvatar,
                      size: widget.compact ? 18 : 20,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        widget.product.sellerName,
                        style: AppTypography.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (widget.product.sellerVerified)
                      const Icon(
                        Icons.verified,
                        size: 14,
                        color: AppColors.primary,
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  widget.product.title,
                  style: AppTypography.body.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: widget.compact ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: widget.compact ? 2 : 4),
                Text(
                  formatCurrency(widget.product.displayPrice),
                  style: AppTypography.subheading.copyWith(
                    color: AppColors.primary,
                    fontSize: widget.compact ? 14 : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    return ThriftCard(
      onTap: widget.onTap,
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(
              imageUrl: widget.product.imageUrl,
              width: 60,
              height: 60,
              fit: BoxFit.cover,
              placeholder: (_, _) => Container(
                color: AppColors.primaryLight,
                width: 60,
                height: 60,
              ),
            ),
          ),
          const SizedBox(width: AppConstants.spacingMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.product.title,
                  style: AppTypography.body,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  formatCurrency(widget.product.price),
                  style: AppTypography.subheading.copyWith(
                    color: AppColors.primary,
                    fontSize: 14,
                  ),
                ),
                Text(
                  '${widget.product.viewCount} views • ${widget.product.likesCount} likes',
                  style: AppTypography.caption,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
