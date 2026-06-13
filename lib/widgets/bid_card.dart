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
    final currentHighest = product.currentBid ?? product.startingBid ?? product.price;

    return ThriftCard(
      onTap: onTap,
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(
              imageUrl: product.imageUrl,
              width: 72,
              height: 72,
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(color: AppColors.primaryLight, width: 72, height: 72),
            ),
          ),
          const SizedBox(width: AppConstants.spacingMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(product.title, style: AppTypography.body.copyWith(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(product.sellerName, style: AppTypography.caption),
                const SizedBox(height: 4),
                Text('Your bid: ${formatCurrency(bid.amount)}', style: AppTypography.caption.copyWith(color: AppColors.primary, fontWeight: FontWeight.w600)),
                Text(
                  'Current highest: ${formatCurrency(currentHighest)}',
                  style: AppTypography.caption.copyWith(
                    color: isWinning ? AppColors.success : AppColors.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (product.bidEndTime != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.timer, size: 14, color: AppColors.secondary),
                      const SizedBox(width: 4),
                      CountdownTimer(endTime: product.bidEndTime!),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Column(
            children: [
              ThriftBadge(
                label: isWinning ? 'Winning' : 'Outbid',
                variant: isWinning ? BadgeVariant.success : BadgeVariant.error,
              ),
              if (!isWinning && onRaiseBid != null) ...[
                const SizedBox(height: 8),
                ThriftButton(
                  label: 'Raise Bid',
                  variant: ThriftButtonVariant.secondary,
                  expand: false,
                  onPressed: onRaiseBid,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class LookingForCard extends StatelessWidget {
  const LookingForCard({
    super.key,
    required this.post,
    this.showRespondButton = false,
    this.onRespond,
  });

  final dynamic post;
  final bool showRespondButton;
  final VoidCallback? onRespond;

  @override
  Widget build(BuildContext context) {
    return ThriftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ThriftAvatar(imageUrl: post.buyerAvatar, size: 36),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(post.buyerName, style: AppTypography.body.copyWith(fontWeight: FontWeight.w600)),
                    Text(formatRelativeTime(post.createdAt), style: AppTypography.caption),
                  ],
                ),
              ),
              if (post.responseCount > 0)
                ThriftBadge(label: '${post.responseCount} responses', variant: BadgeVariant.neutral),
            ],
          ),
          const SizedBox(height: 12),
          Text(post.title, style: AppTypography.subheading),
          const SizedBox(height: 4),
          Text(post.description, style: AppTypography.body, maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 8),
          Text(
            '${formatCurrency(post.budgetMin)} – ${formatCurrency(post.budgetMax)}',
            style: AppTypography.subheading.copyWith(color: AppColors.primary, fontSize: 14),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            children: [
              if (post.size != null) ThriftBadge(label: 'Size ${post.size}', variant: BadgeVariant.neutral),
              ThriftBadge(label: post.category.label, variant: BadgeVariant.primary),
              ThriftBadge(label: post.location, variant: BadgeVariant.neutral),
            ],
          ),
          if (showRespondButton) ...[
            const SizedBox(height: 12),
            ThriftButton(
              label: 'I Have This!',
              variant: ThriftButtonVariant.secondary,
              onPressed: onRespond ?? () {},
            ),
          ],
        ],
      ),
    );
  }
}
