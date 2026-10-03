import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../models/enums.dart';
import '../../../../models/order_model.dart';
import '../../../../widgets/delivery_timeline.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../../trust_safety/presentation/widgets/order_review_cta.dart';
import '../../controllers/seller_orders_controller.dart';
import '../../../buyer/presentation/widgets/item_return_panel.dart';
import '../widgets/delivery_pin_entry.dart';
import '../widgets/record_delivery_problem_sheet.dart';

class SellerOrderDetailScreen extends StatelessWidget {
  const SellerOrderDetailScreen({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SellerOrdersController>();
    if (controller.isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }
    final order = controller.order;
    if (order == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(controller.errorMessage ?? 'Not found')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('#${order.orderNumber}'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppConstants.spacingMd),
          children: [
            ThriftCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Buyer details', style: AppTypography.subheading),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      ThriftAvatar(imageUrl: order.buyerAvatar, size: 40),
                      const SizedBox(width: 12),
                      Text(order.buyerName, style: AppTypography.body),
                    ],
                  ),
                  Text(
                    order.addressMissing
                        ? 'Buyer has not attached a delivery address yet.'
                        : order.shippingAddress,
                    style: AppTypography.caption,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ThriftCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (order.items.isEmpty) ...[
                    Text(order.productTitle, style: AppTypography.subheading),
                    Text(
                      'Qty: ${order.quantity} • Size: ${order.size ?? 'N/A'}',
                      style: AppTypography.caption,
                    ),
                  ] else
                    for (final item in order.items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.title, style: AppTypography.subheading),
                            Text(
                              'Qty: ${item.quantity}${item.size != null ? ' • Size: ${item.size}' : ''}',
                              style: AppTypography.caption,
                            ),
                          ],
                        ),
                      ),
                  const Divider(),
                  _row('Subtotal', formatCurrency(order.amount)),
                  _row('Shipping', formatCurrency(order.shippingFee)),
                  _row('Platform fee', formatCurrency(order.platformFee)),
                  _row('Total', formatCurrency(order.total), bold: true),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ThriftCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Payment status', style: AppTypography.subheading),
                  const SizedBox(height: 8),
                  ThriftBadge(
                    label: order.isPaymentPending
                        ? 'Checkout in progress'
                        : order.isFailedCheckout
                        ? 'Checkout not completed'
                        : orderStatusLabel(order.status),
                    variant: order.isToShip
                        ? BadgeVariant.success
                        : BadgeVariant.neutral,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    order.isPaymentPending
                        ? 'This is not a sale yet. Fulfillment starts only after PayMongo confirms payment.'
                        : order.isFailedCheckout
                        ? 'The buyer did not complete payment. This is not a sale.'
                        : order.isCompleted
                        ? 'This transaction has been completed.'
                        : order.isDisputed
                        ? 'A delivery problem was reported. Automatic completion is paused.'
                        : order.isDeliveryFailed
                        ? 'Delivery was not completed. The parcel should not have been left with the buyer.'
                        : order.isRefundedSale
                        ? 'The buyer was refunded. This amount is not available as earnings.'
                        : 'PayMongo confirmed this payment. Arrange a freelance rider when you are ready.',
                    style: AppTypography.caption,
                  ),
                ],
              ),
            ),
            if (order.isCompleted) ...[
              const SizedBox(height: 16),
              OrderReviewCta(
                order: order,
                existing: controller.reviewFor(order.id),
                ratingBuyer: true,
                onReturned: () => context.read<SellerOrdersController>().load(
                  showSpinner: false,
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => context.push(
                    RouteNames.reportUser(
                      userId: order.buyerId,
                      orderId: order.id,
                    ),
                  ),
                  child: const Text('Report this buyer'),
                ),
              ),
            ],
            if (order.itemReturn != null) ...[
              const SizedBox(height: 16),
              ThriftCard(
                child: ItemReturnPanel(
                  itemReturn: order.itemReturn!,
                  buyerView: false,
                  isBusy: controller.isUpdatingDelivery,
                  onArrange: () async {
                    await context.push(RouteNames.arrangeReturnFor(order.id));
                    if (!context.mounted) return;
                    await context.read<SellerOrdersController>().load(
                      showSpinner: false,
                    );
                  },
                  onConfirmReceived: () async {
                    final error = await context
                        .read<SellerOrdersController>()
                        .confirmReturnReceived();
                    if (!context.mounted) return;
                    showThriftSnackBar(
                      context,
                      error ?? 'Item return confirmed.',
                      isError: error != null,
                    );
                  },
                ),
              ),
            ],
            if (!order.isPaymentPending && !order.isFailedCheckout) ...[
              const SizedBox(height: 16),
              ThriftCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (order.shipment != null)
                      RiderInfoCard(shipment: order.shipment!, buyerView: false)
                    else ...[
                      Text('Delivery', style: AppTypography.subheading),
                      const SizedBox(height: 8),
                      Text(
                        'Freelance / Local Rider · Seller Arranged',
                        style: AppTypography.caption,
                      ),
                    ],
                    const SizedBox(height: 16),
                    DeliveryTimeline(order: order),
                    if (order.shipment != null &&
                        !order.shipment!.canEditRider &&
                        order.shipment!.hasRider) ...[
                      Text(
                        'Rider details are locked while delivery is in progress.',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (order.shipment?.isOutForDelivery == true) ...[
                      Text(
                        'Do not instruct your rider to leave the parcel without obtaining the buyer\'s Delivery PIN.',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.secondary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      DeliveryPinEntry(
                        isLoading: controller.isUpdatingDelivery,
                        onSubmit: (pin) async {
                          if (pin.length != 6) {
                            showThriftSnackBar(
                              context,
                              'Enter the 6-digit Delivery PIN.',
                              isError: true,
                            );
                            return;
                          }
                          final error = await context
                              .read<SellerOrdersController>()
                              .verifyDeliveryPin(pin);
                          if (!context.mounted) return;
                          showThriftSnackBar(
                            context,
                            error ?? 'Delivery verified.',
                            isError: error != null,
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      ThriftButton(
                        label: 'Record delivery problem',
                        variant: ThriftButtonVariant.outline,
                        onPressed: controller.isUpdatingDelivery
                            ? null
                            : () => _recordFailure(context),
                      ),
                    ],
                    if (order.canArrangeDelivery) ...[
                      const SizedBox(height: 8),
                      ThriftButton(
                        label: order.shipment?.hasRider == true
                            ? 'Update rider'
                            : 'Arrange Delivery',
                        onPressed: () async {
                          await context.push(
                            RouteNames.arrangeDeliveryFor(order.id),
                          );
                          if (!context.mounted) return;
                          await context.read<SellerOrdersController>().load(
                            showSpinner: false,
                          );
                        },
                      ),
                    ],
                    ..._milestoneButtons(context, order, controller),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _milestoneButtons(
    BuildContext context,
    OrderModel order,
    SellerOrdersController controller,
  ) {
    final status = order.shipment?.deliveryStatus;
    final actions = <(String, String)>[];
    if (status == DeliveryStatus.riderAssigned) {
      actions.add(('ready_for_pickup', 'Mark Ready for Pickup'));
    }
    if (status == DeliveryStatus.readyForPickup) {
      actions.add(('picked_up', 'Mark Picked Up'));
    }
    if (status == DeliveryStatus.pickedUp) {
      actions.add(('out_for_delivery', 'Mark Out for Delivery'));
    }
    return [
      for (final action in actions) ...[
        const SizedBox(height: 12),
        ThriftButton(
          label: action.$2,
          onPressed: controller.isUpdatingDelivery
              ? null
              : () async {
                  final error = await context
                      .read<SellerOrdersController>()
                      .advanceDelivery(action.$1);
                  if (!context.mounted) return;
                  if (error != null) {
                    showThriftSnackBar(context, error, isError: true);
                  }
                },
        ),
      ],
    ];
  }

  Future<void> _recordFailure(BuildContext context) async {
    final selection = await RecordDeliveryProblemSheet.show(context);
    if (selection == null || !context.mounted) return;
    final error = await context
        .read<SellerOrdersController>()
        .markDeliveryFailed(
          reason: selection.reason.dbValue,
          details: selection.details,
        );
    if (!context.mounted) return;
    showThriftSnackBar(
      context,
      error ?? 'Delivery marked as not completed.',
      isError: error != null,
    );
  }

  Widget _row(String l, String v, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(l, style: AppTypography.caption),
        Text(
          v,
          style: bold
              ? AppTypography.subheading.copyWith(color: AppColors.primary)
              : AppTypography.body,
        ),
      ],
    ),
  );
}
