import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../models/enums.dart';
import '../../../../providers/data_provider.dart';
import '../../../../widgets/thrift_widgets.dart';

class OrderTrackingScreen extends StatelessWidget {
  const OrderTrackingScreen({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context) {
    final order = context.watch<DataProvider>().orderById(orderId);
    if (order == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('Not found')));

    final steps = [
      _Step('Order Placed', OrderStatus.placed, 'Your order has been placed'),
      _Step('Payment Confirmed', OrderStatus.paymentConfirmed, 'Payment verified'),
      _Step('Seller Preparing', OrderStatus.preparing, 'Seller is packing your item'),
      _Step('Shipped', OrderStatus.shipped, 'Package handed to courier'),
      _Step('Out for Delivery', OrderStatus.outForDelivery, 'Courier is on the way'),
      _Step('Delivered', OrderStatus.delivered, 'Package delivered'),
    ];

    final statusIndex = _statusIndex(order.status);

    return Scaffold(
      appBar: AppBar(title: Text('Track #${order.orderNumber}'), leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop())),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppConstants.spacingMd),
          children: [
            ...steps.asMap().entries.map((e) {
              final done = e.key <= statusIndex;
              final current = e.key == statusIndex;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: done ? AppColors.primary : AppColors.border,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(done ? Icons.check : Icons.circle_outlined, color: Colors.white, size: 16),
                      ),
                      if (e.key < steps.length - 1)
                        Container(width: 2, height: 40, color: done ? AppColors.primary : AppColors.border),
                    ],
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.value.title, style: AppTypography.subheading.copyWith(color: current ? AppColors.primary : null)),
                          Text(e.value.description, style: AppTypography.caption),
                          if (done) Text(order.createdAt.toString().split('.').first, style: AppTypography.caption.copyWith(color: AppColors.textHint)),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            }),
            if (order.trackingNumber != null)
              ThriftCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Delivery Details', style: AppTypography.subheading),
                    const SizedBox(height: 8),
                    Text('Courier: ${order.courier ?? "J&T Express"}', style: AppTypography.body),
                    Text('Tracking: ${order.trackingNumber}', style: AppTypography.body),
                    if (order.estimatedDelivery != null)
                      Text('Est. delivery: ${order.estimatedDelivery!.toString().split(' ').first}', style: AppTypography.caption),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  int _statusIndex(OrderStatus status) {
    switch (status) {
      case OrderStatus.placed:
      case OrderStatus.paymentPending:
        return 0;
      case OrderStatus.paymentConfirmed:
        return 1;
      case OrderStatus.preparing:
        return 2;
      case OrderStatus.shipped:
        return 3;
      case OrderStatus.outForDelivery:
        return 4;
      case OrderStatus.delivered:
        return 5;
      case OrderStatus.cancelled:
        return 0;
    }
  }
}

class _Step {
  const _Step(this.title, this.status, this.description);
  final String title;
  final OrderStatus status;
  final String description;
}
