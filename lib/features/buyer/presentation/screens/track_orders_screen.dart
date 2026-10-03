import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../models/order_model.dart';
import '../../../../widgets/empty_state.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../controllers/buyer_orders_controller.dart';
import '../buyer_delivery_status.dart';

class TrackOrdersScreen extends StatelessWidget {
  const TrackOrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<BuyerOrdersController>();
    final orders = controller.orders
        .where((order) => order.isTrackable)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Track Order'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(child: _body(context, controller, orders)),
    );
  }

  Widget _body(
    BuildContext context,
    BuyerOrdersController controller,
    List<OrderModel> orders,
  ) {
    if (controller.isLoading && controller.orders.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }
    if (controller.errorMessage != null && controller.orders.isEmpty) {
      return ErrorState(
        message: controller.errorMessage ??
            'Unable to load your orders. Please try again.',
        onRetry: controller.load,
      );
    }
    if (orders.isEmpty) {
      return EmptyState(
        icon: Icons.local_shipping_outlined,
        title: 'No orders to track',
        message:
            'Orders that are being prepared or delivered will appear here.',
        actionLabel: 'Browse items',
        onAction: () => context.go(RouteNames.buyerHome),
      );
    }
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: controller.load,
      child: ListView.separated(
        padding: const EdgeInsets.all(AppConstants.spacingMd),
        itemCount: orders.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, i) {
          if (i == 0) {
            return Text('Active Deliveries', style: AppTypography.heading);
          }
          return _TrackOrderCard(order: orders[i - 1]);
        },
      ),
    );
  }
}

class _TrackOrderCard extends StatelessWidget {
  const _TrackOrderCard({required this.order});

  final OrderModel order;

  @override
  Widget build(BuildContext context) {
    final status = buyerDeliveryStatus(order);
    return Semantics(
      button: true,
      label: 'View tracking for ${order.productTitle}',
      child: ThriftCard(
        onTap: () => context.push(RouteNames.trackOrderFor(order.id)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ProductImage(imageUrl: order.productImage),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.productTitle,
                        style: AppTypography.subheading,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Order #${order.orderNumber}',
                        style: AppTypography.caption,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Divider(height: 1),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(top: 5),
                  decoration: BoxDecoration(
                    color: status.color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        status.title,
                        style: AppTypography.body.copyWith(
                          fontWeight: FontWeight.w600,
                          color: status.color,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(status.message, style: AppTypography.caption),
                      if (status.channelLine != null) ...[
                        const SizedBox(height: 2),
                        Text(status.channelLine!, style: AppTypography.caption),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'View tracking',
                    style: AppTypography.label.copyWith(
                      color: AppColors.primaryDark,
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    color: AppColors.primaryDark,
                    semanticLabel: 'View tracking',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductImage extends StatelessWidget {
  const _ProductImage({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: imageUrl.isEmpty
          ? Container(
              width: 56,
              height: 56,
              color: AppColors.surfaceVariant,
              child: const Icon(Icons.image_outlined, size: 22),
            )
          : CachedNetworkImage(
              imageUrl: imageUrl,
              width: 56,
              height: 56,
              fit: BoxFit.cover,
              placeholder: (_, _) => Container(
                width: 56,
                height: 56,
                color: AppColors.surfaceVariant,
              ),
              errorWidget: (_, _, _) => Container(
                width: 56,
                height: 56,
                color: AppColors.surfaceVariant,
                child: const Icon(Icons.image_outlined, size: 22),
              ),
            ),
    );
  }
}
