import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/fulfillment_sla.dart';
import '../../../../models/community_report_model.dart';
import '../../../../models/order_model.dart';
import '../../../../models/return_shipment.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../../trust_safety/data/review_rules.dart';
import '../../data/buyer_purchase_category.dart';
import '../buyer_delivery_status.dart';

class MyPurchaseOrderCard extends StatelessWidget {
  const MyPurchaseOrderCard({
    super.key,
    required this.order,
    required this.category,
    this.reviewActionKind,
    this.onReviewTap,
    this.orderReport,
  });

  final OrderModel order;
  final BuyerPurchaseCategory category;
  final ReviewActionKind? reviewActionKind;
  final VoidCallback? onReviewTap;
  final CommunityReportModel? orderReport;

  @override
  Widget build(BuildContext context) {
    if (category == BuyerPurchaseCategory.toPay) {
      return const SizedBox.shrink();
    }

    final status = _statusView();
    final lines = order.items.isNotEmpty ? order.items : null;

    return Semantics(
      button: true,
      label: 'Order from ${order.sellerName}',
      child: ThriftCard(
        onTap: () => _openDetails(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.storefront_outlined,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    order.sellerName,
                    style: AppTypography.caption.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '#${order.orderNumber}',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textHint,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (lines != null && lines.length > 1)
              ...lines.map((line) => _LineRow(line: line))
            else
              _PrimaryLine(order: order),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Divider(height: 1),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 8,
                  height: 8,
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
                          fontSize: 14,
                        ),
                      ),
                      if (status.message.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(status.message, style: AppTypography.caption),
                      ],
                    ],
                  ),
                ),
                Text(
                  formatCurrency(order.total),
                  style: AppTypography.subheading.copyWith(
                    color: AppColors.primaryDark,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
            if (_actionLabel() != null || _showFulfillmentReport()) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    if (_showFulfillmentReport())
                      _FulfillmentReportButton(
                        sla: fulfillmentSlaForOrder(order, report: orderReport),
                        onReport: () => context.push(
                          RouteNames.orderFulfillmentReportFor(order.id),
                        ),
                        onReview: orderReport == null
                            ? null
                            : () => context.push(
                                RouteNames.reportDetailFor(orderReport!.id),
                              ),
                      ),
                    if (_actionLabel() != null)
                      OutlinedButton(
                        onPressed: () => _onAction(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: const BorderSide(color: AppColors.primary),
                          minimumSize: const Size(0, 44),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(
                          _actionLabel()!,
                          style: AppTypography.caption.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  _StatusCopy _statusView() {
    final bucket = category == BuyerPurchaseCategory.all
        ? buyerPurchaseCategory(order)
        : category;

    if (bucket == BuyerPurchaseCategory.cancelled) {
      return _StatusCopy(
        title: 'Cancelled',
        message: 'Payment deadline expired.',
        color: AppColors.textSecondary,
      );
    }
    if (bucket == BuyerPurchaseCategory.returnRefund) {
      final returnStatus = order.itemReturn?.status;
      final deliveryHint = order.shipment?.deliveryStatus.label;
      if (returnStatus != null && returnStatus.isNotEmpty) {
        final base = returnStatusLabel(returnStatus);
        final message = deliveryHint != null && deliveryHint.isNotEmpty
            ? '$base · Delivery: $deliveryHint'
            : base;
        return _StatusCopy(
          title: 'Return / Refund',
          message: message,
          color: AppColors.warning,
        );
      }
      if (order.isDisputed) {
        return _StatusCopy(
          title: 'Return / Refund',
          message: deliveryHint != null && deliveryHint.isNotEmpty
              ? 'Under review · Delivery: $deliveryHint'
              : 'Your request is being reviewed.',
          color: AppColors.warning,
        );
      }
      return const _StatusCopy(
        title: 'Return / Refund',
        message: 'Your request is being reviewed.',
        color: AppColors.warning,
      );
    }
    if (bucket == BuyerPurchaseCategory.completed) {
      return const _StatusCopy(
        title: 'Completed',
        message: 'Transaction finished.',
        color: AppColors.success,
      );
    }

    final delivery = buyerDeliveryStatus(order);
    final sla = fulfillmentSlaForOrder(order, report: orderReport);
    var message = delivery.message;
    if (sla.cta == FulfillmentReportCta.waiting &&
        sla.reportUnlocksAt != null) {
      message =
          '${delivery.message} You can report a delay in ${formatFulfillmentRemaining(sla.reportUnlocksAt)}.';
    } else if (sla.cta == FulfillmentReportCta.ready) {
      message =
          '${delivery.message} The seller has not updated this order. You can report a problem. Unprocessed orders are cancelled 72 hours after payment.';
    } else if (sla.cta == FulfillmentReportCta.underReview) {
      message = '${delivery.message} Your report is under review.';
    }
    return _StatusCopy(
      title: delivery.title,
      message: message,
      color: sla.delayedForAdmin ? AppColors.warning : delivery.color,
    );
  }

  bool _showFulfillmentReport() {
    final sla = fulfillmentSlaForOrder(order, report: orderReport);
    return sla.cta != FulfillmentReportCta.hidden;
  }

  String? _actionLabel() {
    if (category == BuyerPurchaseCategory.cancelled) return null;
    final bucket = category == BuyerPurchaseCategory.all
        ? buyerPurchaseCategory(order)
        : category;
    if (bucket == BuyerPurchaseCategory.completed && reviewActionKind != null) {
      return reviewActionLabel(reviewActionKind!, ratingBuyer: false);
    }
    if (bucket == BuyerPurchaseCategory.toReceive) return 'Track delivery';
    if (category == BuyerPurchaseCategory.toPay) return 'Pay now';
    return 'View order';
  }

  void _onAction(BuildContext context) {
    final bucket = category == BuyerPurchaseCategory.all
        ? buyerPurchaseCategory(order)
        : category;
    if (bucket == BuyerPurchaseCategory.completed &&
        reviewActionKind != null &&
        onReviewTap != null) {
      onReviewTap!();
      return;
    }
    _openDetails(context);
  }

  void _openDetails(BuildContext context) {
    final bucket = category == BuyerPurchaseCategory.all
        ? buyerPurchaseCategory(order)
        : category;
    if (bucket == BuyerPurchaseCategory.completed &&
        reviewActionKind == ReviewActionKind.leave) {
      onReviewTap?.call();
      return;
    }
    context.push(RouteNames.trackOrderFor(order.id));
  }
}

class _FulfillmentReportButton extends StatelessWidget {
  const _FulfillmentReportButton({
    required this.sla,
    required this.onReport,
    this.onReview,
  });

  final FulfillmentSlaView sla;
  final VoidCallback onReport;
  final VoidCallback? onReview;

  @override
  Widget build(BuildContext context) {
    if (sla.cta == FulfillmentReportCta.underReview) {
      return OutlinedButton(
        onPressed: onReview,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.warning,
          side: const BorderSide(color: AppColors.warning),
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
        child: Text(
          'Under review',
          style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700),
        ),
      );
    }
    final waiting = sla.cta == FulfillmentReportCta.waiting;
    return Semantics(
      button: true,
      enabled: !waiting,
      label: waiting
          ? 'Report a problem available in ${formatFulfillmentRemaining(sla.reportUnlocksAt)}'
          : 'Report a problem with this order',
      child: OutlinedButton(
        onPressed: waiting ? null : onReport,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.error,
          side: BorderSide(color: waiting ? AppColors.border : AppColors.error),
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
        child: Text(
          waiting
              ? 'Report in ${formatFulfillmentRemaining(sla.reportUnlocksAt)}'
              : 'Report a problem',
          style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _StatusCopy {
  const _StatusCopy({
    required this.title,
    required this.message,
    required this.color,
  });

  final String title;
  final String message;
  final Color color;
}

class _PrimaryLine extends StatelessWidget {
  const _PrimaryLine({required this.order});

  final OrderModel order;

  @override
  Widget build(BuildContext context) {
    final qty = order.quantity;
    final unit = order.amount / (qty > 0 ? qty : 1);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Thumb(imageUrl: order.productImage),
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
                'Qty $qty · ${formatCurrency(unit)}',
                style: AppTypography.caption,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({required this.line});

  final OrderLineItem line;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Thumb(imageUrl: line.imageUrl ?? ''),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.title,
                  style: AppTypography.body.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  'Qty ${line.quantity} · ${formatCurrency(line.unitPrice)}',
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

class _Thumb extends StatelessWidget {
  const _Thumb({required this.imageUrl});

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
