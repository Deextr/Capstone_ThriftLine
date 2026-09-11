import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../../profile/data/address_service.dart';
import '../../controllers/buyer_orders_controller.dart';

class OrderConfirmationScreen extends StatelessWidget {
  const OrderConfirmationScreen({super.key, required this.orderId});

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

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(AppConstants.spacingLg),
            child: Column(
              children: [
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle,
                    size: 64,
                    color: AppColors.success,
                  ),
                ),
                const SizedBox(height: 24),
                Text('Order placed', style: AppTypography.display),
                Text(
                  'Order #${order.orderNumber}',
                  style: AppTypography.body.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Payment is pending. No funds have been collected yet.',
                  style: AppTypography.caption,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ThriftCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.items.length > 1
                            ? '${order.items.length} items from ${order.sellerName}'
                            : order.productTitle,
                        style: AppTypography.subheading,
                      ),
                      Text(
                        'Seller: ${order.sellerName}',
                        style: AppTypography.caption,
                      ),
                      const Divider(),
                      for (final item in order.items)
                        _row(
                          '${item.title} × ${item.quantity}',
                          formatCurrency(item.lineTotal),
                        ),
                      _row('Subtotal', formatCurrency(order.amount)),
                      _row('Shipping', formatCurrency(order.shippingFee)),
                      _row('Platform fee', formatCurrency(order.platformFee)),
                      _row('Total', formatCurrency(order.total), bold: true),
                      _row('Payment', 'Pending'),
                      _row(
                        'Delivery',
                        order.addressMissing
                            ? 'Address needed'
                            : order.shippingAddress,
                      ),
                    ],
                  ),
                ),
                if (order.addressMissing) ...[
                  const SizedBox(height: 16),
                  ThriftButton(
                    label: controller.isSavingAddress
                        ? 'Saving address…'
                        : 'Add delivery address',
                    variant: ThriftButtonVariant.secondary,
                    onPressed: controller.isSavingAddress
                        ? null
                        : () async {
                            await context.push(RouteNames.addresses);
                            if (!context.mounted) return;
                            final saved = await AddressService(
                              context.read<SupabaseService>(),
                            ).defaultAddress();
                            if (saved == null) {
                              if (context.mounted) {
                                showThriftSnackBar(
                                  context,
                                  'Save an address, then attach it here.',
                                  isError: true,
                                );
                              }
                              return;
                            }
                            final error = await controller.setAddress(saved.id);
                            if (!context.mounted) return;
                            showThriftSnackBar(
                              context,
                              error ?? 'Delivery address saved.',
                              isError: error != null,
                            );
                          },
                  ),
                ],
                const SizedBox(height: 32),
                ThriftButton(
                  label: 'Track order',
                  onPressed: () => context.push('/track-order/$orderId'),
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
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(child: Text(label, style: AppTypography.caption)),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: bold
                ? AppTypography.subheading.copyWith(color: AppColors.primary)
                : AppTypography.body,
          ),
        ),
      ],
    ),
  );
}
