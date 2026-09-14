import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../models/enums.dart';
import '../../../trust_safety/data/review_rules.dart';
import '../../controllers/buyer_orders_controller.dart';

class PurchaseHistoryScreen extends StatelessWidget {
  const PurchaseHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<BuyerOrdersController>();
    final orders = controller.orders
        .where((order) => order.showsInPurchaseHistory)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Purchase History'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: controller.isLoading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              )
            : orders.isEmpty
            ? Center(
                child: Text(
                  controller.errorMessage ?? 'No purchases yet',
                  style: AppTypography.body,
                ),
              )
            : RefreshIndicator(
                color: AppColors.primary,
                onRefresh: controller.load,
                child: ListView.builder(
                  itemCount: orders.length,
                  itemBuilder: (_, i) {
                    final o = orders[i];
                    return Column(
                      children: [
                        ListTile(
                          title: Text(
                            o.productTitle,
                            style: AppTypography.body,
                          ),
                          subtitle: Text(
                            o.isCompleted
                                ? '#${o.orderNumber} · ${reviewActionLabel(reviewActionKind(controller.reviewFor(o.id)), ratingBuyer: false)}'
                                : '#${o.orderNumber} · ${orderStatusLabel(o.status)}',
                          ),
                          trailing: Text(
                            formatCurrency(o.total),
                            style: AppTypography.subheading.copyWith(
                              color: AppColors.primary,
                              fontSize: 14,
                            ),
                          ),
                          onTap: () async {
                            if (o.isCompleted) {
                              await context.push(
                                RouteNames.leaveReviewFor(o.id),
                              );
                              if (context.mounted) {
                                await controller.load(showSpinner: false);
                              }
                              return;
                            }
                            context.push(RouteNames.trackOrderFor(o.id));
                          },
                        ),
                      ],
                    );
                  },
                ),
              ),
      ),
    );
  }
}
