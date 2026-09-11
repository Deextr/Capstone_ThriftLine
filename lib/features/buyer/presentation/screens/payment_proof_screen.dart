import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../widgets/thrift_widgets.dart';

class PaymentProofScreen extends StatelessWidget {
  const PaymentProofScreen({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.spacingMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Payment comes later', style: AppTypography.heading),
              const SizedBox(height: 8),
              Text(
                'This order exists and payment is still pending. GCash, Maya, and PayMongo are not collected in this step.',
                style: AppTypography.body,
              ),
              const Spacer(),
              ThriftButton(
                label: 'Back to order',
                onPressed: () => context.go('/order-confirm/$orderId'),
              ),
              const SizedBox(height: 12),
              ThriftButton(
                label: 'Continue shopping',
                variant: ThriftButtonVariant.outline,
                onPressed: () => context.go(RouteNames.buyerHome),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
