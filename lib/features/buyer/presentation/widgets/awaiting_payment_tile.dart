import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../models/order_model.dart';

class AwaitingPaymentTile extends StatelessWidget {
  const AwaitingPaymentTile({super.key, required this.order});

  final OrderModel order;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      title: Text(order.productTitle, style: AppTypography.body),
      subtitle: Text(
        'Awaiting payment · #${order.orderNumber}',
        style: AppTypography.caption,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            formatCurrency(order.total),
            style: AppTypography.subheading.copyWith(
              color: AppColors.primary,
              fontSize: 14,
            ),
          ),
          Text(
            'Continue',
            style: AppTypography.caption.copyWith(
              color: AppColors.primaryDark,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      onTap: () => context.push(RouteNames.paymentForOrder(order.id)),
    );
  }
}
