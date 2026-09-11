import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../models/enums.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../controllers/buyer_orders_controller.dart';

class OrderTrackingScreen extends StatelessWidget {
  const OrderTrackingScreen({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<BuyerOrdersController>();
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
        body: Center(child: Text(controller.errorMessage ?? 'Order not found')),
      );
    }

    final steps = [
      _Step('Order placed', 'Your order exists and is waiting for payment.'),
      _Step('Payment', 'Payment is not collected yet. That comes later.'),
      _Step('To ship', 'The seller can ship after payment is confirmed.'),
      _Step('Shipped', 'The package has been handed to a courier.'),
      _Step('Delivered', 'The package was delivered.'),
    ];

    final statusIndex = _statusIndex(order.status);

    return Scaffold(
      appBar: AppBar(
        title: Text('Track #${order.orderNumber}'),
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
                  Text(order.productTitle, style: AppTypography.subheading),
                  Text(
                    'Payment pending · ${orderStatusLabel(order.status)}',
                    style: AppTypography.caption,
                  ),
                  if (order.shippingAddress.isNotEmpty)
                    Text(order.shippingAddress, style: AppTypography.caption),
                ],
              ),
            ),
            const SizedBox(height: 16),
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
                        child: Icon(
                          done ? Icons.check : Icons.circle_outlined,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                      if (e.key < steps.length - 1)
                        Container(
                          width: 2,
                          height: 40,
                          color: done ? AppColors.primary : AppColors.border,
                        ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.value.title,
                            style: AppTypography.subheading.copyWith(
                              color: current ? AppColors.primary : null,
                            ),
                          ),
                          Text(
                            e.value.description,
                            style: AppTypography.caption,
                          ),
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
                    Text('Delivery details', style: AppTypography.subheading),
                    const SizedBox(height: 8),
                    Text(
                      'Courier: ${order.courier ?? 'Not set'}',
                      style: AppTypography.body,
                    ),
                    Text(
                      'Tracking: ${order.trackingNumber}',
                      style: AppTypography.body,
                    ),
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
      case OrderStatus.outForDelivery:
        return 3;
      case OrderStatus.delivered:
        return 4;
      case OrderStatus.cancelled:
        return 0;
    }
  }
}

class _Step {
  const _Step(this.title, this.description);
  final String title;
  final String description;
}
