import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/constants/app_colors.dart';
import '../core/constants/app_constants.dart';
import '../core/constants/app_typography.dart';
import '../core/utils/formatters.dart';
import '../models/bid_model.dart';
import '../models/enums.dart';
import '../models/product_model.dart';
import 'countdown_timer.dart';
import 'thrift_widgets.dart';

class BidCard extends StatelessWidget {
  const BidCard({
    super.key,
    required this.bid,
    required this.product,
    this.onTap,
    this.onRaiseBid,
  });

  final UserBid bid;
  final ProductModel product;
  final VoidCallback? onTap;
  final VoidCallback? onRaiseBid;

  @override
  Widget build(BuildContext context) {
    final isWinning = bid.status == BidStatus.winning;
    final currentHighest =
        product.currentBid ?? product.startingBid ?? product.price;

    return ThriftCard(
      onTap: onTap,
      padding: EdgeInsets.zero,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status strip
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: isWinning ? AppColors.primary : AppColors.textHint,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(AppConstants.radiusLg),
                  bottomLeft: Radius.circular(AppConstants.radiusLg),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppConstants.spacingMd),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        imageUrl: product.imageUrl,
                        width: 72,
                        height: 72,
                        fit: BoxFit.cover,
                        placeholder: (_, _) => Container(
                          color: AppColors.primaryLight,
                          width: 72,
                          height: 72,
                        ),
                        errorWidget: (_, _, _) => Container(
                          color: AppColors.primaryLight,
                          width: 72,
                          height: 72,
                          child: const Icon(
                            Icons.image_outlined,
                            color: AppColors.textHint,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppConstants.spacingMd),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            product.title,
                            style: AppTypography.body.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(product.sellerName, style: AppTypography.caption),
                          const SizedBox(height: 8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text('Your bid: ', style: AppTypography.caption),
                              Text(
                                formatCurrency(bid.amount),
                                style: AppTypography.subheading.copyWith(
                                  color: AppColors.textPrimary,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text('Highest: ', style: AppTypography.caption),
                              Text(
                                formatCurrency(currentHighest),
                                style: AppTypography.subheading.copyWith(
                                  color: isWinning ? AppColors.success : AppColors.textSecondary,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isWinning ? "You're #1" : "Outbid by ${formatCurrency(currentHighest - bid.amount)}",
                            style: AppTypography.caption.copyWith(
                              color: isWinning ? AppColors.success : AppColors.textSecondary,
                            ),
                          ),
                          if (product.bidEndTime != null) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceVariant,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.timer,
                                    size: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                  const SizedBox(width: 4),
                                  CountdownTimer(
                                    endTime: product.bidEndTime!,
                                    style: AppTypography.caption.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        ThriftBadge(
                          label: isWinning ? 'Winning' : 'Outbid',
                          variant: isWinning ? BadgeVariant.success : BadgeVariant.warning,
                        ),
                        if (!isWinning && onRaiseBid != null) ...[
                          const SizedBox(height: 12),
                          ThriftButton(
                            label: 'Raise Bid',
                            variant: ThriftButtonVariant.outline,
                            expand: false,
                            onPressed: onRaiseBid,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

