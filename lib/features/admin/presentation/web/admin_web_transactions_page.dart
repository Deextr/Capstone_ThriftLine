import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../controllers/admin_transactions_controller.dart';
import 'admin_web_table.dart';

class AdminWebTransactionsPage extends StatelessWidget {
  const AdminWebTransactionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AdminTransactionsController>();
    return ColoredBox(
      color: AppColors.background,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          DropdownButton<String?>(
            value: null,
            hint: const Text('Payment status'),
            items: const [
              DropdownMenuItem(value: null, child: Text('All')),
              DropdownMenuItem(value: 'paid', child: Text('Paid')),
              DropdownMenuItem(value: 'pending', child: Text('Pending')),
              DropdownMenuItem(value: 'failed', child: Text('Failed')),
            ],
            onChanged: controller.setPaymentStatus,
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
            emptyMessage: 'No transactions found for this range.',
            columns: const [
              'Order',
              'Buyer',
              'Seller',
              'Gross',
              'Platform fee',
              'Seller amount',
              'Status',
              'Date',
            ],
            rows: [
              for (final row in controller.rows)
                [
                  Text(row.orderNumber),
                  Text(row.buyerName),
                  Text(row.sellerName),
                  Text(formatCurrency(row.grossAmount)),
                  Text(formatCurrency(row.platformFee)),
                  Text(formatCurrency(row.sellerAmount)),
                  Text(row.paymentStatus),
                  Text(formatFullDate(row.createdAt)),
                ],
            ],
          ),
        ],
      ),
    );
  }
}
