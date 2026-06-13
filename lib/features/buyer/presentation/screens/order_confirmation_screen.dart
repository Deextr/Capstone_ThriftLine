import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../models/enums.dart';
import '../../../../providers/data_provider.dart';
import '../../../../widgets/thrift_widgets.dart';

class OrderConfirmationScreen extends StatelessWidget {
  const OrderConfirmationScreen({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context) {
    final order = context.watch<DataProvider>().orderById(orderId);
    if (order == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('Order not found')));

    final needsProof = order.paymentMethod != PaymentMethod.cod &&
        order.status == OrderStatus.paymentPending;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.spacingLg),
          child: Column(
            children: [
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle, size: 64, color: AppColors.success),
              ),
              const SizedBox(height: 24),
              Text('Order Placed!', style: AppTypography.display),
              Text('Order #${order.orderNumber}', style: AppTypography.body.copyWith(color: AppColors.textSecondary)),
              const SizedBox(height: 24),
              ThriftCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(order.productTitle, style: AppTypography.subheading),
                    Text('Seller: ${order.sellerName}', style: AppTypography.caption),
                    const Divider(),
                    _row('Item', formatCurrency(order.amount)),
                    _row('Shipping', formatCurrency(order.shippingFee)),
                    _row('Platform fee', formatCurrency(order.platformFee)),
                    _row('Total', formatCurrency(order.total), bold: true),
                    _row('Payment', order.paymentMethod.label),
                    _row('Delivery', order.deliveryMethod.label),
                    const SizedBox(height: 16),
                    Container(
                      height: 80,
                      width: 80,
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.qr_code, size: 48),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (needsProof)
                ThriftButton(
                  label: 'Upload Payment Proof',
                  variant: ThriftButtonVariant.secondary,
                  onPressed: () => context.push('/payment-proof/$orderId'),
                ),
              const SizedBox(height: 12),
              ThriftButton(
                label: 'Track Order',
                onPressed: () => context.push('/track-order/$orderId'),
              ),
              const SizedBox(height: 12),
              ThriftButton(
                label: 'Continue Shopping',
                variant: ThriftButtonVariant.outline,
                onPressed: () => context.go(RouteNames.buyerHome),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: AppTypography.caption),
            Text(value, style: bold ? AppTypography.subheading.copyWith(color: AppColors.primary) : AppTypography.body),
          ],
        ),
      );
}
