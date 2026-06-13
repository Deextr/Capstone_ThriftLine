import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../models/enums.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../providers/data_provider.dart';
import '../../../../widgets/empty_state.dart';
import '../../../../widgets/thrift_widgets.dart';

class SellerOrdersTab extends StatefulWidget {
  const SellerOrdersTab({super.key});

  @override
  State<SellerOrdersTab> createState() => _SellerOrdersTabState();
}

class _SellerOrdersTabState extends State<SellerOrdersTab> with SingleTickerProviderStateMixin {
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
    final auth = context.watch<AuthProvider>();
    final data = context.watch<DataProvider>();
    final orders = data.ordersForSeller(auth.user?.id ?? 'seller_carla');

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppConstants.spacingMd),
            child: Text('Orders', style: AppTypography.heading),
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
            child: TabBarView(
              controller: _tab,
              children: [
                _list(orders.where((o) => o.status == OrderStatus.placed || o.status == OrderStatus.paymentPending).toList()),
                _list(orders.where((o) => o.status == OrderStatus.paymentConfirmed || o.status == OrderStatus.preparing).toList()),
                _list(orders.where((o) => o.status == OrderStatus.shipped).toList()),
                _list(orders.where((o) => o.status == OrderStatus.delivered).toList()),
                _list(orders.where((o) => o.status == OrderStatus.cancelled).toList()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _list(List orders) {
    if (orders.isEmpty) {
      return const EmptyState(icon: Icons.inventory_2, title: 'No orders', message: 'Orders will appear here');
    }
    return ListView.builder(
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
                    ThriftBadge(label: o.status.name, variant: BadgeVariant.neutral),
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
                      child: CachedNetworkImage(imageUrl: o.productImage, width: 48, height: 48, fit: BoxFit.cover),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(o.productTitle, style: AppTypography.body)),
                    Text(formatCurrency(o.total), style: AppTypography.subheading.copyWith(color: AppColors.primary, fontSize: 14)),
                  ],
                ),
                const SizedBox(height: 8),
                Text('${o.paymentMethod.label} • ${o.deliveryMethod.label}', style: AppTypography.caption),
                const SizedBox(height: 8),
                if (o.status == OrderStatus.placed || o.status == OrderStatus.paymentPending)
                  Row(
                    children: [
                      Expanded(child: ThriftButton(label: 'Confirm Order', expand: false, onPressed: () {
                        context.read<DataProvider>().updateOrderStatus(o.id, OrderStatus.preparing);
                        showThriftSnackBar(context, 'Order confirmed');
                      })),
                      const SizedBox(width: 8),
                      ThriftButton(label: 'Cancel', variant: ThriftButtonVariant.outline, color: AppColors.error, expand: false, onPressed: () {
                        context.read<DataProvider>().updateOrderStatus(o.id, OrderStatus.cancelled);
                      }),
                    ],
                  ),
                if (o.status == OrderStatus.preparing)
                  ThriftButton(label: 'Mark as Shipped', onPressed: () {
                    context.read<DataProvider>().updateOrderStatus(o.id, OrderStatus.shipped, tracking: 'JNT${DateTime.now().millisecondsSinceEpoch}');
                    showThriftSnackBar(context, 'Marked as shipped');
                  }),
              ],
            ),
          ),
        );
      },
    );
  }
}
