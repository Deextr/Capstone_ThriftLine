import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../models/order_model.dart';
import '../../../../widgets/thrift_widgets.dart';
import 'payment_deadline_text.dart';

class AwaitingPaymentTile extends StatelessWidget {
  const AwaitingPaymentTile({super.key, required this.order});

  final OrderModel order;

  @override
  Widget build(BuildContext context) {
    final expired = !order.isPaymentWindowOpen && order.paymentDueAt != null;
    final extraCount = order.items.length > 1 ? order.items.length - 1 : 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ThriftCard(
        padding: const EdgeInsets.all(14),
        onTap: expired
            ? null
            : () => context.push(RouteNames.paymentForOrder(order.id)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: expired
                        ? AppColors.surfaceVariant
                        : AppColors.warning.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    expired ? 'Payment expired' : 'Awaiting payment',
                    style: AppTypography.caption.copyWith(
                      color: expired
                          ? AppColors.textSecondary
                          : AppColors.warning,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  formatCurrency(order.total),
                  style: AppTypography.subheading.copyWith(
                    color: AppColors.primaryDark,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ProductThumb(
                  imageUrl: order.productImage,
                  extraCount: extraCount,
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
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        expired
                            ? 'The payment window for this auction win has ended.'
                            : 'You won this auction. Complete payment before the deadline.',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      if (order.paymentDueAt != null) ...[
                        const SizedBox(height: 6),
                        PaymentDeadlineText(
                          due: order.paymentDueAt!,
                          style: AppTypography.caption.copyWith(
                            fontWeight: FontWeight.w600,
                            color: expired
                                ? AppColors.textHint
                                : AppColors.primaryDark,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (!expired) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 40,
                child: ElevatedButton(
                  onPressed: () =>
                      context.push(RouteNames.paymentForOrder(order.id)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    'Pay now',
                    style: AppTypography.caption.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProductThumb extends StatelessWidget {
  const _ProductThumb({required this.imageUrl, required this.extraCount});

  final String imageUrl;
  final int extraCount;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: imageUrl.isEmpty
              ? Container(
                  width: 64,
                  height: 64,
                  color: AppColors.surfaceVariant,
                  child: const Icon(
                    Icons.image_outlined,
                    color: AppColors.textHint,
                  ),
                )
              : CachedNetworkImage(
                  imageUrl: imageUrl,
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
                    child: const Icon(
                      Icons.image_outlined,
                      color: AppColors.textHint,
                    ),
                  ),
                ),
        ),
        if (extraCount > 0)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.textPrimary.withValues(alpha: 0.78),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  bottomRight: Radius.circular(10),
                ),
              ),
              child: Text(
                '+$extraCount',
                style: AppTypography.caption.copyWith(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
