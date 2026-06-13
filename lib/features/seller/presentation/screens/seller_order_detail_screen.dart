import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../models/enums.dart';
import '../../../../providers/data_provider.dart';
import '../../../../widgets/thrift_widgets.dart';

class SellerOrderDetailScreen extends StatelessWidget {
  const SellerOrderDetailScreen({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context) {
    final order = context.watch<DataProvider>().orderById(orderId);
    if (order == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('Not found')));

    return Scaffold(
      appBar: AppBar(title: Text('#${order.orderNumber}'), leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop())),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppConstants.spacingMd),
          children: [
            ThriftCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Buyer Details', style: AppTypography.subheading),
                  const SizedBox(height: 8),
                  Row(children: [ThriftAvatar(imageUrl: order.buyerAvatar, size: 40), const SizedBox(width: 12), Text(order.buyerName, style: AppTypography.body)]),
                  Text(order.shippingAddress, style: AppTypography.caption),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ThriftCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(order.productTitle, style: AppTypography.subheading),
                  Text('Qty: ${order.quantity} • Size: ${order.size ?? "N/A"}', style: AppTypography.caption),
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
                  Text('Payment Status', style: AppTypography.subheading),
                  ThriftBadge(
                    label: order.paymentProofSubmitted ? 'Confirmed' : 'Pending',
                    variant: order.paymentProofSubmitted ? BadgeVariant.success : BadgeVariant.warning,
                  ),
                  if (order.paymentProofSubmitted)
                    Container(
                      height: 100,
                      margin: const EdgeInsets.only(top: 8),
                      decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(8)),
                      child: const Center(child: Icon(Icons.receipt_long, size: 40)),
                    ),
                  if (order.paymentProofSubmitted && order.status == OrderStatus.paymentConfirmed)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: ThriftButton(
                        label: 'Confirm Payment',
                        onPressed: () {
                          context.read<DataProvider>().updateOrderStatus(orderId, OrderStatus.preparing);
                          showThriftSnackBar(context, 'Payment confirmed');
                        },
                      ),
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
            Text(v, style: bold ? AppTypography.subheading.copyWith(color: AppColors.primary) : AppTypography.body),
          ],
        ),
      );
}
