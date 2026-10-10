import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../models/order_model.dart';
import '../../../../models/review_model.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../controllers/buyer_to_rate_controller.dart';
import '../../data/buyer_to_rate_buckets.dart';
import '../../data/review_rules.dart';
import '../widgets/star_rating_input.dart';

class BuyerToRateScreen extends StatefulWidget {
  const BuyerToRateScreen({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  State<BuyerToRateScreen> createState() => _BuyerToRateScreenState();
}

class _BuyerToRateScreenState extends State<BuyerToRateScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 1),
    );
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _openReview(BuildContext context, String orderId) async {
    final didSubmit = await context.push<bool>(
      RouteNames.leaveReviewFor(orderId),
    );
    if (!context.mounted) return;
    await context.read<BuyerToRateController>().load(showSpinner: false);
    if (didSubmit == true) {
      _tabs.animateTo(1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<BuyerToRateController>();
    final pendingCount = controller.pendingCount;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Ratings & Reviews'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: TabBar(
              controller: _tabs,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.primary,
              indicatorWeight: 3,
              labelStyle: AppTypography.label.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
              unselectedLabelStyle: AppTypography.label.copyWith(
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
              tabs: [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('To Rate'),
                      if (pendingCount > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '$pendingCount',
                            style: AppTypography.caption.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Tab(text: 'My Reviews'),
              ],
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: controller.isLoading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              )
            : TabBarView(
                controller: _tabs,
                children: [
                  RefreshIndicator(
                    color: AppColors.primary,
                    onRefresh: () => controller.load(),
                    child: _PendingList(
                      orders: controller.pendingOrders,
                      errorMessage: controller.errorMessage,
                      onRate: (orderId) => _openReview(context, orderId),
                    ),
                  ),
                  RefreshIndicator(
                    color: AppColors.primary,
                    onRefresh: () => controller.load(),
                    child: _ReviewHistoryList(
                      entries: controller.ratedPurchases,
                      errorMessage: controller.errorMessage,
                      onEdit: (orderId) => _openReview(context, orderId),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _PendingList extends StatelessWidget {
  const _PendingList({
    required this.orders,
    required this.onRate,
    this.errorMessage,
  });

  final List<OrderModel> orders;
  final ValueChanged<String> onRate;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 32),
        children: [
          const SizedBox(height: 96),
          Center(
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_outline_rounded,
                size: 38,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'All caught up!',
            textAlign: TextAlign.center,
            style: AppTypography.heading.copyWith(fontSize: 20),
          ),
          const SizedBox(height: 8),
          Text(
            errorMessage ?? 'You have no orders waiting for a review.',
            textAlign: TextAlign.center,
            style: AppTypography.body.copyWith(color: AppColors.textSecondary),
          ),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      itemCount: orders.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, index) {
        final order = orders[index];
        return _PendingOrderCard(order: order, onRate: () => onRate(order.id));
      },
    );
  }
}

class _ReviewHistoryList extends StatelessWidget {
  const _ReviewHistoryList({
    required this.entries,
    required this.onEdit,
    this.errorMessage,
  });

  final List<BuyerRatedPurchase> entries;
  final ValueChanged<String> onEdit;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 32),
        children: [
          const SizedBox(height: 96),
          Center(
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.rate_review_outlined,
                size: 38,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'No reviews yet',
            textAlign: TextAlign.center,
            style: AppTypography.heading.copyWith(fontSize: 20),
          ),
          const SizedBox(height: 8),
          Text(
            errorMessage ??
                'Completed purchases you\'ve reviewed will appear here.',
            textAlign: TextAlign.center,
            style: AppTypography.body.copyWith(color: AppColors.textSecondary),
          ),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      itemCount: entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, index) {
        final entry = entries[index];
        final canEdit = canEditReview(entry.review.createdAt);
        return _SubmittedReviewCard(
          entry: entry,
          canEdit: canEdit,
          onEdit: () => onEdit(entry.order.id),
        );
      },
    );
  }
}

class _PendingOrderCard extends StatelessWidget {
  const _PendingOrderCard({required this.order, required this.onRate});

  final OrderModel order;
  final VoidCallback onRate;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: order.productImage.isEmpty
                    ? Container(
                        width: 64,
                        height: 64,
                        color: AppColors.surfaceVariant,
                        child: Icon(
                          Icons.checkroom_outlined,
                          color: AppColors.textHint,
                        ),
                      )
                    : CachedNetworkImage(
                        imageUrl: order.productImage,
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                        placeholder: (_, _) => Container(
                          width: 64,
                          height: 64,
                          color: AppColors.surfaceVariant,
                        ),
                        errorWidget: (_, _, _) => Container(
                          width: 64,
                          height: 64,
                          color: AppColors.surfaceVariant,
                          child: Icon(
                            Icons.image_not_supported_outlined,
                            color: AppColors.textHint,
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      order.productTitle,
                      style: AppTypography.body.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.storefront_outlined,
                          size: 14,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            order.sellerName,
                            style: AppTypography.caption.copyWith(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${formatCurrency(order.total)} · Delivered ${formatCompactDate(order.createdAt)}',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.primaryDark,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Order #${order.orderNumber}',
                style: AppTypography.caption.copyWith(
                  color: AppColors.textHint,
                ),
              ),
              ThriftButton(
                label: 'Rate Now',
                icon: Icons.star_outline_rounded,
                expand: false,
                onPressed: onRate,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SubmittedReviewCard extends StatelessWidget {
  const _SubmittedReviewCard({
    required this.entry,
    required this.canEdit,
    required this.onEdit,
  });

  final BuyerRatedPurchase entry;
  final bool canEdit;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final order = entry.order;
    final review = entry.review;
    final comment = review.comment.trim();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: order.productImage.isEmpty
                    ? Container(
                        width: 44,
                        height: 44,
                        color: AppColors.surfaceVariant,
                        child: Icon(
                          Icons.checkroom_outlined,
                          size: 20,
                          color: AppColors.textHint,
                        ),
                      )
                    : CachedNetworkImage(
                        imageUrl: order.productImage,
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                        placeholder: (_, _) => Container(
                          width: 44,
                          height: 44,
                          color: AppColors.surfaceVariant,
                        ),
                        errorWidget: (_, _, _) => Container(
                          width: 44,
                          height: 44,
                          color: AppColors.surfaceVariant,
                          child: Icon(
                            Icons.image_not_supported_outlined,
                            size: 20,
                            color: AppColors.textHint,
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      order.productTitle,
                      style: AppTypography.body.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(
                          Icons.storefront_outlined,
                          size: 13,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            order.sellerName,
                            style: AppTypography.caption.copyWith(
                              color: AppColors.textSecondary,
                              fontSize: 12,
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
              if (canEdit)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.edit_outlined, size: 14),
                  label: const Text(
                    'Edit',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  onPressed: onEdit,
                ),
            ],
          ),
          const SizedBox(height: 10),
          Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              StarRatingReadout(
                value: review.rating.toDouble(),
                size: 18,
                showNumber: true,
              ),
              Text(
                formatFullDate(review.createdAt),
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          if (comment.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                comment,
                style: AppTypography.body.copyWith(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ),
          ],
          if (review.photos.isNotEmpty) ...[
            const SizedBox(height: 10),
            _ReviewPhotoStrip(photos: review.photos),
          ],
        ],
      ),
    );
  }
}

class _ReviewPhotoStrip extends StatelessWidget {
  const _ReviewPhotoStrip({required this.photos});

  final List<ReviewPhoto> photos;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: photos.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, index) {
          final url = photos[index].publicUrl;
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: url == null || url.isEmpty
                ? Container(
                    width: 72,
                    height: 72,
                    color: AppColors.surfaceVariant,
                  )
                : CachedNetworkImage(
                    imageUrl: url,
                    width: 72,
                    height: 72,
                    fit: BoxFit.cover,
                  ),
          );
        },
      ),
    );
  }
}
