import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/utils/formatters.dart';
import '../../controllers/admin_orders_list_controller.dart';
import 'admin_web_table.dart';

class AdminWebOrdersPage extends StatelessWidget {
  const AdminWebOrdersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AdminOrdersListController>();
    return ColoredBox(
      color: AppColors.background,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          DropdownButton<String?>(
            value: controller.statusFilter,
            hint: const Text('Order status'),
            items: const [
              DropdownMenuItem(value: null, child: Text('All statuses')),
              DropdownMenuItem(value: 'payment_pending', child: Text('Awaiting payment')),
              DropdownMenuItem(value: 'paid', child: Text('Paid / To ship')),
              DropdownMenuItem(value: 'shipped', child: Text('Shipped')),
              DropdownMenuItem(value: 'completed', child: Text('Completed')),
              DropdownMenuItem(value: 'cancelled', child: Text('Cancelled')),
            ],
            onChanged: controller.setStatusFilter,
          ),
          if (controller.errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              controller.errorMessage!,
              style: AppTypography.caption.copyWith(color: AppColors.error),
            ),
          ],
          const SizedBox(height: 16),
          AdminWebTable(
            isLoading: controller.isLoading,
            emptyMessage: 'No orders found for this filter.',
            columns: const [
              'Order',
              'Buyer',
              'Seller',
              'Amount',
              'Payment',
              'Status',
              'Created',
              '',
            ],
            rows: [
              for (final order in controller.rows)
                [
                  Text(order.orderNumber),
                  Text(order.buyerName),
                  Text(order.sellerName),
                  Text(formatCurrency(order.totalAmount)),
                  Text(order.paymentStatus),
                  Text(order.statusLabel),
                  Text(formatFullDate(order.createdAt)),
                  TextButton(
                    onPressed: () =>
                        context.push(RouteNames.adminOrderDetailFor(order.orderId)),
                    child: const Text('View order'),
                  ),
                ],
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(
                '${controller.total} orders',
                style: AppTypography.caption,
              ),
              const Spacer(),
              IconButton(
                onPressed: controller.page > 0
                    ? () => controller.setPage(controller.page - 1)
                    : null,
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                onPressed: () => controller.setPage(controller.page + 1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
