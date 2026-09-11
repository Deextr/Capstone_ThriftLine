import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../models/enums.dart';
import '../../../../models/order_model.dart';
import '../../../../widgets/empty_state.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../controllers/seller_orders_controller.dart';

class SellerOrdersTab extends StatefulWidget {
  const SellerOrdersTab({super.key});

  @override
  State<SellerOrdersTab> createState() => _SellerOrdersTabState();
}

class _SellerOrdersTabState extends State<SellerOrdersTab>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SellerOrdersController>();
    final orders = controller.orders;

    return SafeArea(
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.all(AppConstants.spacingMd),
              child: Text('Orders', style: AppTypography.heading),
            ),
          ),
          TabBar(
            controller: _tab,
            isScrollable: true,
            labelColor: AppColors.primary,
            tabs: const [
              Tab(text: 'Pending'),
              Tab(text: 'To Ship'),
              Tab(text: 'Shipped'),
              Tab(text: 'Completed'),
              Tab(text: 'Cancelled'),
            ],
          ),
          Expanded(
            child: controller.isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  )
                : TabBarView(
                    controller: _tab,
                    children: [
                      _list(
                        orders
                            .where(
                              (o) =>
                                  o.status == OrderStatus.placed ||
                                  o.status == OrderStatus.paymentPending,
                            )
                            .toList(),
                      ),
                      _list(
                        orders
                            .where(
                              (o) =>
                                  o.status == OrderStatus.paymentConfirmed ||
                                  o.status == OrderStatus.preparing,
                            )
                            .toList(),
                      ),
                      _list(
                        orders
                            .where((o) => o.status == OrderStatus.shipped)
                            .toList(),
                      ),
                      _list(
                        orders
                            .where((o) => o.status == OrderStatus.delivered)
                            .toList(),
                      ),
                      _list(
                        orders
                            .where((o) => o.status == OrderStatus.cancelled)
                            .toList(),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _list(List<OrderModel> orders) {
    if (orders.isEmpty) {
      return const EmptyState(
        icon: Icons.inventory_2,
        title: 'No orders',
        message: 'Orders will appear here',
      );
    }
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () => context.read<SellerOrdersController>().load(),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: orders.length,
        itemBuilder: (_, i) {
          final o = orders[i];
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: ThriftCard(
              onTap: () => context.push('/seller-order/${o.id}'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('#${o.orderNumber}', style: AppTypography.caption),
                      ThriftBadge(
                        label: orderStatusLabel(o.status),
                        variant: BadgeVariant.neutral,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      ThriftAvatar(imageUrl: o.buyerAvatar, size: 32),
                      const SizedBox(width: 8),
                      Text(o.buyerName, style: AppTypography.body),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: CachedNetworkImage(
                          imageUrl: o.productImage,
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                          placeholder: (_, _) =>
                              Container(color: AppColors.surfaceVariant),
                          errorWidget: (_, _, _) => Container(
                            color: AppColors.surfaceVariant,
                            child: const Icon(Icons.image_outlined, size: 20),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(o.productTitle, style: AppTypography.body),
                      ),
                      Text(
                        formatCurrency(o.total),
                        style: AppTypography.subheading.copyWith(
                          color: AppColors.primary,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    o.isPaymentPending
                        ? 'Awaiting payment'
                        : '${o.paymentMethod.label} · ${o.deliveryMethod.label}',
                    style: AppTypography.caption,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
