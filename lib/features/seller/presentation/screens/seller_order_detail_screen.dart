import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../models/enums.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../controllers/seller_orders_controller.dart';

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
                        ? 'Awaiting payment'
                        : orderStatusLabel(order.status),
                    variant: order.isPaymentPending
                        ? BadgeVariant.warning
                        : BadgeVariant.neutral,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Payment collection is a later step. Do not mark this order as paid here.',
                    style: AppTypography.caption,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
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
