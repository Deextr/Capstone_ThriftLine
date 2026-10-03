import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/utils/rider_privacy.dart';
import '../../../../models/order_model.dart';
import '../../../../widgets/delivery_timeline.dart';
import '../../../../widgets/empty_state.dart';
import '../../../../widgets/rider_contact_card.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../widgets/item_return_panel.dart';
import '../../../trust_safety/presentation/widgets/order_review_cta.dart';
import '../../controllers/buyer_orders_controller.dart';
import '../buyer_delivery_status.dart';

class OrderTrackingScreen extends StatelessWidget {
  const OrderTrackingScreen({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<BuyerOrdersController>();
    if (controller.isLoading) {
      return const Scaffold(body: _TrackingLoadingView());
    }

    final order = controller.order;
    if (order == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Track Order'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
        ),
        body: ErrorState(
          message: 'Unable to load delivery details. Please try again.',
          onRetry: controller.load,
        ),
      );
    }

    if (order.isFailedCheckout) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go(RouteNames.cart);
      });
      return const Scaffold(body: _TrackingLoadingView());
    }

    if (order.isPaymentPending) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          context.go(RouteNames.paymentForOrder(orderId));
        }
      });
      return const Scaffold(body: _TrackingLoadingView());
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Track Order'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: controller.load,
          child: ListView(
            padding: const EdgeInsets.all(AppConstants.spacingMd),
            children: [
              _StatusHero(order: order),
              const SizedBox(height: 16),
              ThriftCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Delivery Progress', style: AppTypography.subheading),
                    const SizedBox(height: 12),
                    DeliveryTimeline(order: order, compact: true),
                    if (order.shipment == null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Tracking information will appear here once your order ships.',
                        style: AppTypography.caption,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _ProductSummary(order: order),
              if (order.shipment?.isLocalRider == true &&
                  order.shipment?.shouldShowBuyerRiderInfo == true) ...[
                const SizedBox(height: 16),
                ThriftCard(
                  child: BuyerRiderContactCard(
                    shipment: order.shipment!,
                    onCall: () => _openRiderAction(context, call: true),
                    onMessage: () => _openRiderAction(context, call: false),
                  ),
                ),
              ],
              if (order.shipment?.isOfficialCourier == true &&
                  ((order.courier?.trim().isNotEmpty ?? false) ||
                      (order.trackingNumber?.trim().isNotEmpty ?? false))) ...[
                const SizedBox(height: 16),
                ThriftCard(
                  child: BuyerCourierInfo(
                    order: order,
                    onTrack: () => _trackPackage(context),
                  ),
                ),
              ],
              if (order.shippingAddress.trim().isNotEmpty) ...[
                const SizedBox(height: 16),
                ThriftCard(child: _AddressSection(order: order)),
              ],
              if (order.shipment?.pinAvailable == true) ...[
                const SizedBox(height: 16),
                ThriftCard(
                  child: _DeliveryPinCard(pin: controller.deliveryPin),
                ),
              ],
              if (order.isInspecting &&
                  !order.isCompleted &&
                  !order.isDisputed) ...[
                const SizedBox(height: 16),
                ThriftCard(
                  child: _InspectionCard(
                    order: order,
                    isBusy: controller.isUpdatingDelivery,
                    onConfirm: () async {
                      final error = await context
                          .read<BuyerOrdersController>()
                          .confirmDelivery();
                      if (!context.mounted) return;
                      showThriftSnackBar(
                        context,
                        error ??
                            'Receipt recorded. Inspection can still continue.',
                        isError: error != null,
                      );
                    },
                    onReport: () => _reportProblem(context),
                  ),
                ),
              ],
              if (order.itemReturn != null) ...[
                const SizedBox(height: 16),
                ThriftCard(
                  child: ItemReturnPanel(
                    itemReturn: order.itemReturn!,
                    buyerView: true,
                    isBusy: controller.isUpdatingDelivery,
                    onHandOff: () async {
                      final error = await context
                          .read<BuyerOrdersController>()
                          .confirmReturnHandedOff();
                      if (!context.mounted) return;
                      showThriftSnackBar(
                        context,
                        error ?? 'Handoff recorded.',
                        isError: error != null,
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 16),
              _OrderSummary(order: order),
              if (order.isCompleted) ...[
                const SizedBox(height: 16),
                ThriftCard(
                  child: _NoticeSection(
                    title: 'Order completed',
                    message:
                        'Delivery was verified with your Delivery PIN and the inspection window is complete.',
                    color: AppColors.success,
                    icon: Icons.check_circle_outline,
                  ),
                ),
                const SizedBox(height: 12),
                OrderReviewCta(
                  order: order,
                  existing: controller.reviewFor(order.id),
                  ratingBuyer: false,
                  onReturned: () => context.read<BuyerOrdersController>().load(
                    showSpinner: false,
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => context.push(
                      RouteNames.reportUser(
                        userId: order.sellerId,
                        orderId: order.id,
                      ),
                    ),
                    child: const Text('Report this seller'),
                  ),
                ),
              ],
              if (order.isDisputed) ...[
                const SizedBox(height: 16),
                ThriftCard(
                  child: _NoticeSection(
                    title: 'Delivery problem reported',
                    message:
                        'Automatic completion is paused while ThriftLine reviews the report.',
                    color: AppColors.warning,
                    icon: Icons.report_problem_outlined,
                  ),
                ),
              ],
              if (order.isDeliveryFailed) ...[
                const SizedBox(height: 16),
                ThriftCard(
                  child: _NoticeSection(
                    title: 'Delivery was not completed',
                    message:
                        order.shipment?.deliveryFailureSummary ??
                        'A delivery problem was reported.',
                    color: AppColors.warning,
                    icon: Icons.error_outline,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openRiderAction(
    BuildContext context, {
    required bool call,
  }) async {
    final error = await (call
        ? context.read<BuyerOrdersController>().callRider()
        : context.read<BuyerOrdersController>().messageRider());
    if (!context.mounted || error == null) return;
    showThriftSnackBar(context, error, isError: true);
  }

  Future<void> _trackPackage(BuildContext context) async {
    final error = await context.read<BuyerOrdersController>().trackCourier();
    if (!context.mounted || error == null) return;
    showThriftSnackBar(context, error, isError: true);
  }

  void _reportProblem(BuildContext context) {
    context.push(RouteNames.orderDeliveryReportFor(orderId));
  }
}

class _TrackingLoadingView extends StatelessWidget {
  const _TrackingLoadingView();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(AppConstants.spacingMd),
        children: [
          const SizedBox(height: 12),
          Container(
            height: 112,
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            ),
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < 4; i++) ...[
            Container(
              height: i == 2 ? 190 : 72,
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(AppConstants.radiusLg),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _StatusHero extends StatelessWidget {
  const _StatusHero({required this.order});

  final OrderModel order;

  @override
  Widget build(BuildContext context) {
    final status = buyerDeliveryStatus(order);
    return Container(
      padding: const EdgeInsets.all(AppConstants.spacingMd),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: status.color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: status.color,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(status.icon, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status.title,
                  style: AppTypography.heading.copyWith(color: status.color),
                ),
                const SizedBox(height: 3),
                Text(status.message, style: AppTypography.body),
                const SizedBox(height: 8),
                Text(
                  'Order #${order.orderNumber}',
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

class _ProductSummary extends StatelessWidget {
  const _ProductSummary({required this.order});

  final OrderModel order;

  @override
  Widget build(BuildContext context) {
    final item = order.items.isNotEmpty ? order.items.first : null;
    final image = item?.imageUrl ?? order.productImage;
    final title = item?.title ?? order.productTitle;
    final quantity = item?.quantity ?? order.quantity;
    final size = item?.size ?? order.size;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Your Item', style: AppTypography.subheading),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              child: image.trim().isEmpty
                  ? Container(
                      width: 72,
                      height: 72,
                      color: AppColors.surfaceVariant,
                      child: const Icon(Icons.image_outlined),
                    )
                  : CachedNetworkImage(
                      imageUrl: image,
                      width: 72,
                      height: 72,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => Container(
                        width: 72,
                        height: 72,
                        color: AppColors.surfaceVariant,
                        child: const Icon(Icons.image_outlined),
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTypography.body.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (size?.trim().isNotEmpty == true) 'Size $size',
                      'Qty $quantity',
                    ].join('  |  '),
                    style: AppTypography.caption,
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _AddressSection extends StatelessWidget {
  const _AddressSection({required this.order});

  final OrderModel order;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Deliver To', style: AppTypography.subheading),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.location_on_outlined,
              color: AppColors.primaryDark,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(order.shippingAddress, style: AppTypography.body),
            ),
          ],
        ),
      ],
    );
  }
}

class _OrderSummary extends StatelessWidget {
  const _OrderSummary({required this.order});

  final OrderModel order;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 4),
        childrenPadding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
        title: Text('Order Summary', style: AppTypography.subheading),
        subtitle: Text(
          'Total Paid  ${_money(order.total)}',
          style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
        ),
        children: [
          const Divider(height: 1),
          const SizedBox(height: 10),
          _PriceLine(label: 'Item subtotal', value: order.amount),
          _PriceLine(label: 'Shipping', value: order.shippingFee),
          _PriceLine(label: 'Platform fee', value: order.platformFee),
          const Divider(height: 20),
          _PriceLine(label: 'Total Paid', value: order.total, strong: true),
        ],
      ),
    );
  }
}

class _PriceLine extends StatelessWidget {
  const _PriceLine({
    required this.label,
    required this.value,
    this.strong = false,
  });

  final String label;
  final double value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final style = AppTypography.body.copyWith(
      fontWeight: strong ? FontWeight.w700 : FontWeight.w400,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(_money(value), style: style),
        ],
      ),
    );
  }
}

class _NoticeSection extends StatelessWidget {
  const _NoticeSection({
    required this.title,
    required this.message,
    required this.color,
    required this.icon,
  });

  final String title;
  final String message;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTypography.subheading),
              const SizedBox(height: 4),
              Text(message, style: AppTypography.caption),
            ],
          ),
        ),
      ],
    );
  }
}

String _money(double value) => 'PHP ${value.toStringAsFixed(2)}';

class _DeliveryPinCard extends StatelessWidget {
  const _DeliveryPinCard({required this.pin});

  final String? pin;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Delivery PIN', style: AppTypography.subheading),
        const SizedBox(height: 8),
        Text(
          pin ?? 'Loading...',
          style: AppTypography.heading.copyWith(letterSpacing: 6),
        ),
        const SizedBox(height: 8),
        Text(
          'Only give this PIN to the rider after the parcel is physically in your possession.',
          style: AppTypography.caption,
        ),
      ],
    );
  }
}

class _InspectionCard extends StatefulWidget {
  const _InspectionCard({
    required this.order,
    required this.isBusy,
    required this.onConfirm,
    required this.onReport,
  });

  final OrderModel order;
  final bool isBusy;
  final Future<void> Function() onConfirm;
  final VoidCallback onReport;

  @override
  State<_InspectionCard> createState() => _InspectionCardState();
}

class _InspectionCardState extends State<_InspectionCard> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = formatInspectionRemaining(
      widget.order.shipment?.inspectionExpiresAt,
    );
    final confirmed = widget.order.shipment?.buyerConfirmedReceived == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Inspect your order', style: AppTypography.subheading),
        const SizedBox(height: 8),
        Text(
          'Check the item before the inspection window ends.',
          style: AppTypography.caption,
        ),
        const SizedBox(height: 8),
        Text('Time remaining: $remaining', style: AppTypography.body),
        if (confirmed) ...[
          const SizedBox(height: 8),
          Text(
            'You confirmed receiving this order. Inspection can still continue until the window ends.',
            style: AppTypography.caption,
          ),
        ],
        const SizedBox(height: 16),
        ThriftButton(
          label: widget.isBusy ? 'Saving...' : 'I received my order',
          onPressed: widget.isBusy || confirmed ? null : widget.onConfirm,
        ),
        const SizedBox(height: 12),
        ThriftButton(
          label: 'Report a problem',
          variant: ThriftButtonVariant.outline,
          onPressed: widget.isBusy ? null : widget.onReport,
        ),
      ],
    );
  }
}
