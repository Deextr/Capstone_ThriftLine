import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_colors.dart';
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
    this.onSellerTap,
    this.showCountdown = false,
    this.compact = false,
  });

  final ProductModel product;
  final ProductCardVariant variant;
  final VoidCallback? onTap;
  final VoidCallback? onSellerTap;
  final bool showCountdown;
  final bool compact;

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

  // ---------------------------------------------------------------------------
  // Grid card — redesigned to match reference image
  // ---------------------------------------------------------------------------

  Widget _buildGrid(BuildContext context) {
    final data = context.watch<DataProvider>();
    final saved = data.isSaved(widget.product.id);
    final hasBid = widget.product.hasActiveBid;

    return AnimatedScale(
      scale: _isPressed ? 0.965 : 1.0,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) {
          setState(() => _isPressed = false);
          widget.onTap?.call();
        },
        onTapCancel: () => setState(() => _isPressed = false),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.07),
                blurRadius: 14,
                spreadRadius: 0,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Product image — fixed 1:1 aspect ratio ────────────────
                AspectRatio(
                  aspectRatio: 1.0,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Product image — with robust error handling
                      CachedNetworkImage(
                        imageUrl: widget.product.imageUrl,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        memCacheWidth: 400,
                        fadeInDuration: const Duration(milliseconds: 200),
                        placeholder: (_, _) => const _ImagePlaceholder(),
                        errorWidget: (_, _, _) => const _ImagePlaceholder(),
                      ),

                      // Condition badge — top left
                      Positioned(
                        top: 8,
                        left: 8,
                        child: _ConditionBadge(
                          label: widget.product.condition.label,
                        ),
                      ),

                      // Countdown timer pill — top right
                      if (widget.showCountdown &&
                          widget.product.bidEndTime != null)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: _CountdownPill(
                            endTime: widget.product.bidEndTime!,
                          ),
                        ),

                      // Save / heart — bottom right of image
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: _SaveButton(
                          saved: saved,
                          controller: _heartController,
                          onTap: () {
                            _heartController.forward(from: 0);
                            data.toggleSave(widget.product.id);
                          },
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Content section — auto height, no overflow ────────────
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    12,
                    widget.compact ? 6 : 8,
                    12,
                    widget.compact ? 10 : 14,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Brand name
                      if (widget.product.brand != null &&
                          widget.product.brand!.isNotEmpty) ...[
                        Text(
                          widget.product.brand!,
                          style: AppTypography.caption.copyWith(
                            fontSize: widget.compact ? 10 : 11,
                            color: AppColors.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                      ],

                      // Product title
                      Text(
                        widget.product.title,
                        style: AppTypography.body.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: widget.compact ? 12 : 13,
                          height: 1.25,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),

                      SizedBox(height: widget.compact ? 3 : 5),

                      // Seller row
                      GestureDetector(
                        onTap: widget.onSellerTap,
                        behavior: HitTestBehavior.opaque,
                        child: Row(
                          children: [
                            ThriftAvatar(
                              imageUrl: widget.product.sellerAvatar,
                              size: widget.compact ? 16 : 20,
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                widget.product.sellerName,
                                style: AppTypography.caption.copyWith(
                                  fontSize: widget.compact ? 10 : 11,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.textPrimary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (widget.product.sellerVerified)
                              Icon(
                                Icons.verified_rounded,
                                size: widget.compact ? 12 : 14,
                                color: AppColors.primary,
                              ),
                          ],
                        ),
                      ),

                      SizedBox(height: widget.compact ? 3 : 4),

                      // Bid label (conditional)
                      if (hasBid)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 1),
                          child: Text(
                            'Current Bid',
                            style: AppTypography.caption.copyWith(
                              fontSize: widget.compact ? 9 : 10,
                              color: AppColors.textHint,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),

                      // Price + Location row — Flexible prevents overflow
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text(
                              formatCurrency(widget.product.displayPrice),
                              style: AppTypography.subheading.copyWith(
                                color: AppColors.primary,
                                fontSize: widget.compact ? 13 : 14,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3,
                                height: 1.2,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // Location
                          if (widget.product.location != null &&
                              widget.product.location!.isNotEmpty) ...[
                            const SizedBox(width: 4),
                            Icon(
                              Icons.location_on_outlined,
                              size: widget.compact ? 11 : 12,
                              color: AppColors.textHint,
                            ),
                            const SizedBox(width: 2),
                            Flexible(
                              child: Text(
                                widget.product.location!,
                                style: AppTypography.caption.copyWith(
                                  fontSize: widget.compact ? 9 : 10,
                                  color: AppColors.textHint,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // List card (used in search results etc.)
  // ---------------------------------------------------------------------------

  Widget _buildList(BuildContext context) {
    final hasBid = widget.product.hasActiveBid;

    return AnimatedScale(
      scale: _isPressed ? 0.98 : 1.0,
      duration: const Duration(milliseconds: 120),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) {
          setState(() => _isPressed = false);
          widget.onTap?.call();
        },
        onTapCancel: () => setState(() => _isPressed = false),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
            border: Border.all(
              color: AppColors.border.withValues(alpha: 0.5),
            ),
          ),
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Thumbnail with condition badge
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: CachedNetworkImage(
                      imageUrl: widget.product.imageUrl,
                      width: 80,
                      height: 80,
                      fit: BoxFit.cover,
                      placeholder: (_, _) => Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight,
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      errorWidget: (_, _, _) => Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.image_outlined,
                          color: AppColors.textHint,
                        ),
                      ),
                    ),
                  ),
                  // Condition badge on thumbnail
                  Positioned(
                    top: 4,
                    left: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        widget.product.condition.label,
                        style: AppTypography.caption.copyWith(
                          fontSize: 8,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Brand
                    if (widget.product.brand != null &&
                        widget.product.brand!.isNotEmpty)
                      Text(
                        widget.product.brand!,
                        style: AppTypography.caption.copyWith(
                          fontSize: 10,
                          color: AppColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    // Title
                    Text(
                      widget.product.title,
                      style: AppTypography.body.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    // Price row
                    Row(
                      children: [
                        if (hasBid)
                          Text(
                            'Current Bid ',
                            style: AppTypography.caption.copyWith(
                              fontSize: 10,
                              color: AppColors.textHint,
                            ),
                          ),
                        Text(
                          formatCurrency(widget.product.displayPrice),
                          style: AppTypography.subheading.copyWith(
                            color: AppColors.primary,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    // Location
                    if (widget.product.location != null &&
                        widget.product.location!.isNotEmpty)
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on_outlined,
                            size: 12,
                            color: AppColors.textHint,
                          ),
                          const SizedBox(width: 2),
                          Expanded(
                            child: Text(
                              widget.product.location!,
                              style: AppTypography.caption.copyWith(
                                fontSize: 10,
                                color: AppColors.textHint,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helper widgets
// ─────────────────────────────────────────────────────────────────────────────

/// Shimmer-style placeholder shown while the image loads or on error.
class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.primaryLight.withValues(alpha: 0.5),
      child: Center(
        child: Icon(
          Icons.image_outlined,
          color: AppColors.textHint.withValues(alpha: 0.5),
          size: 32,
        ),
      ),
    );
  }
}

/// Condition badge (e.g. "Good", "Like new") — semi-transparent white pill,
/// positioned at the top-left of the image.
class _ConditionBadge extends StatelessWidget {
  const _ConditionBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Text(
        label,
        style: AppTypography.caption.copyWith(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w600,
          fontSize: 11,
        ),
      ),
    );
  }
}

/// Countdown timer pill — primary-colored rounded pill with clock icon,
/// positioned at the top-right of the image.
class _CountdownPill extends StatelessWidget {
  const _CountdownPill({required this.endTime});
  final DateTime endTime;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.35),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.schedule_rounded, color: Colors.white, size: 12),
          const SizedBox(width: 4),
          CountdownTimer(
            endTime: endTime,
            style: AppTypography.caption.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

/// Heart / save button — small white circle with shadow.
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.95),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: AnimatedBuilder(
            animation: controller,
            builder: (_, _) => Icon(
              saved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              color: saved ? AppColors.error : AppColors.textSecondary,
              size: 17,
            ),
          ),
        ),
      ),
    );
  }
}
