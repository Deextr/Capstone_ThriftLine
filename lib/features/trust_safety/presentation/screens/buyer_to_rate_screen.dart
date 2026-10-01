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
    await context.push(RouteNames.leaveReviewFor(orderId));
    if (!context.mounted) return;
    await context.read<BuyerToRateController>().load();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<BuyerToRateController>();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Ratings & Reviews'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.primary,
          tabs: [
            Tab(text: 'To Rate (${controller.pendingCount})'),
            const Tab(text: 'My Reviews'),
          ],
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
          Icon(Icons.star_outline_rounded, size: 44, color: AppColors.textHint),
          const SizedBox(height: 16),
          Text(
            'Nothing to rate right now',
            textAlign: TextAlign.center,
            style: AppTypography.heading.copyWith(fontSize: 20),
          ),
          const SizedBox(height: 8),
          Text(
            errorMessage ??
                'Completed orders you have not reviewed yet will show up here.',
            textAlign: TextAlign.center,
            style: AppTypography.body.copyWith(color: AppColors.textSecondary),
          ),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      itemCount: orders.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
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
          Icon(Icons.rate_review_outlined, size: 44, color: AppColors.textHint),
          const SizedBox(height: 16),
          Text(
            'No reviews yet',
            textAlign: TextAlign.center,
            style: AppTypography.heading.copyWith(fontSize: 20),
          ),
          const SizedBox(height: 8),
          Text(
            errorMessage ??
                'After you rate a seller, your review will appear in this list.',
            textAlign: TextAlign.center,
            style: AppTypography.body.copyWith(color: AppColors.textSecondary),
          ),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      itemCount: entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
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
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _OrderSellerRow(order: order),
            const SizedBox(height: 14),
            ThriftButton(label: 'Rate Now', onPressed: onRate),
          ],
        ),
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
    final review = entry.review;
    final comment = review.comment.trim();

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _OrderSellerRow(order: entry.order),
            const SizedBox(height: 12),
            _ReadOnlyStars(rating: review.rating),
            if (comment.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(comment, style: AppTypography.body),
            ],
            if (review.photos.isNotEmpty) ...[
              const SizedBox(height: 10),
              _ReviewPhotoStrip(photos: review.photos),
            ],
            const SizedBox(height: 10),
            Text(
              'Submitted ${formatFullDate(review.createdAt)}',
              style: AppTypography.caption,
            ),
            if (canEdit) ...[
              const SizedBox(height: 12),
              ThriftButton(
                label: 'Edit Review',
                variant: ThriftButtonVariant.outline,
                onPressed: onEdit,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OrderSellerRow extends StatelessWidget {
  const _OrderSellerRow({required this.order});

  final OrderModel order;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: order.productImage.isEmpty
              ? Container(
                  width: 56,
                  height: 56,
                  color: AppColors.surfaceVariant,
                  child: const Icon(
                    Icons.checkroom_outlined,
                    color: AppColors.textHint,
                  ),
                )
              : CachedNetworkImage(
                  imageUrl: order.productImage,
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                order.productTitle,
                style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                'Seller · ${order.sellerName}',
                style: AppTypography.caption,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReadOnlyStars extends StatelessWidget {
  const _ReadOnlyStars({required this.rating});

  final int rating;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(5, (index) {
        final filled = index < rating;
        return Icon(
          filled ? Icons.star_rounded : Icons.star_border_rounded,
          size: 22,
          color: filled ? AppColors.primary : AppColors.textHint,
        );
      }),
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
