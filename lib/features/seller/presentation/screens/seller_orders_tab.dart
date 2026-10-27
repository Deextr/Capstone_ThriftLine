import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../features/auth/domain/account_mode.dart';
import '../../../../models/order_model.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../providers/notifications_provider.dart';
import '../../../../widgets/empty_state.dart';
import '../../controllers/seller_orders_controller.dart';
import '../../data/seller_order_buckets.dart';
import '../../data/seller_order_tab_notifications.dart';
import '../widgets/seller_order_card.dart';

class SellerOrdersTab extends StatefulWidget {
  const SellerOrdersTab({
    super.key,
    this.initialBucket = SellerOrderBucket.toShip,
  });

  final SellerOrderBucket initialBucket;

  @override
  State<SellerOrdersTab> createState() => _SellerOrdersTabState();
}

class _SellerOrdersTabState extends State<SellerOrdersTab>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(
      length: SellerOrderBucket.values.length,
      vsync: this,
      initialIndex: widget.initialBucket.index,
    );
    _tab.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant SellerOrdersTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialBucket != widget.initialBucket &&
        _tab.index != widget.initialBucket.index) {
      _tab.animateTo(widget.initialBucket.index);
    }
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  int? _tabBadgeCount(
    SellerOrdersController controller,
    NotificationsProvider notifications,
    AuthProvider auth,
    SellerOrderBucket bucket,
  ) {
    if (controller.isLoading && controller.orders.isEmpty) return null;
    if (bucket == SellerOrderBucket.all) return null;

    if (sellerOrderNotificationTabs.contains(bucket)) {
      final orderIds = controller.ordersIn(bucket).map((o) => o.id).toSet();
      final unread = sellerOrderTabUnreadCount(
        items: notifications.items,
        bucket: bucket,
        orderIdsInBucket: orderIds,
        accountMode: AccountMode.seller,
        hasSellerAccess: auth.user?.hasSellerAccess ?? false,
        sellerUserId: auth.user?.id,
      );
      return unread > 0 ? unread : null;
    }

    final count = controller.countIn(bucket);
    return count > 0 ? count : null;
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SellerOrdersController>();
    final notifications = context.watch<NotificationsProvider>();
    final auth = context.watch<AuthProvider>();

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppConstants.spacingMd,
              AppConstants.spacingMd,
              AppConstants.spacingMd,
              8,
            ),
            child: Text('Orders', style: AppTypography.heading),
          ),
          TabBar(
            controller: _tab,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.primary,
            dividerColor: AppColors.divider,
            tabs: [
              for (final bucket in SellerOrderBucket.values)
                Tab(
                  height: 46,
                  child: _StatusTabLabel(
                    label: bucket.tabLabel,
                    count: _tabBadgeCount(
                      controller,
                      notifications,
                      auth,
                      bucket,
                    ),
                    countSemanticsSuffix:
                        sellerOrderNotificationTabs.contains(bucket)
                        ? 'unread notifications'
                        : 'orders',
                    selected: _tab.index == bucket.index,
                  ),
                ),
            ],
          ),
          Expanded(
            child: _body(controller, notifications, auth),
          ),
        ],
      ),
    );
  }

  Widget _body(
    SellerOrdersController controller,
    NotificationsProvider notifications,
    AuthProvider auth,
  ) {
    if (controller.isLoading && controller.orders.isEmpty) {
      return const _OrdersLoadingView();
    }
    if (controller.errorMessage != null && controller.orders.isEmpty) {
      return ErrorState(
        message:
            controller.errorMessage ??
            'Unable to load orders. Please try again.',
        onRetry: controller.load,
      );
    }
    return TabBarView(
      controller: _tab,
      children: [
        for (final bucket in SellerOrderBucket.values)
          _OrderBucketList(
            bucket: bucket,
            orders: controller.ordersIn(bucket),
            notifications: notifications,
            auth: auth,
            onRefresh: controller.load,
          ),
      ],
    );
  }
}

class _StatusTabLabel extends StatelessWidget {
  const _StatusTabLabel({
    required this.label,
    required this.count,
    required this.countSemanticsSuffix,
    required this.selected,
  });

  final String label;
  final int? count;
  final String countSemanticsSuffix;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final shown = count != null && count! > 0;
    return Semantics(
      selected: selected,
      label: shown ? '$label, $count $countSemanticsSuffix' : label,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(
            padding: EdgeInsets.only(right: shown ? 12 : 0, top: shown ? 4 : 0),
            child: Text(label),
          ),
          if (shown)
            Positioned(
              right: -4,
              top: -2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.error,
                  borderRadius: BorderRadius.circular(10),
                ),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                child: Text(
                  '${count!}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _OrderBucketList extends StatelessWidget {
  const _OrderBucketList({
    required this.bucket,
    required this.orders,
    required this.notifications,
    required this.auth,
    required this.onRefresh,
  });

  final SellerOrderBucket bucket;
  final List<OrderModel> orders;
  final NotificationsProvider notifications;
  final AuthProvider auth;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return EmptyState(
        icon: bucket == SellerOrderBucket.toShip
            ? Icons.local_shipping_outlined
            : bucket == SellerOrderBucket.all
            ? Icons.receipt_long_outlined
            : Icons.inventory_2_outlined,
        title: bucket.emptyTitle,
        message: bucket.emptyMessage,
      );
    }
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        itemCount: orders.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, i) {
          final order = orders[i];
          final hasUnread = sellerOrderNotificationTabs.contains(bucket)
              ? sellerOrderHasUnreadTabNotifications(
                  items: notifications.items,
                  bucket: bucket,
                  orderId: order.id,
                  accountMode: AccountMode.seller,
                  hasSellerAccess: auth.user?.hasSellerAccess ?? false,
                  sellerUserId: auth.user?.id,
                )
              : false;
          return SellerOrderCard(
            order: order,
            hasUnreadNotification: hasUnread,
            onTap: () => context.push('/seller-order/${order.id}'),
          );
        },
      ),
    );
  }
}

class _OrdersLoadingView extends StatelessWidget {
  const _OrdersLoadingView();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppConstants.spacingMd),
      children: [
        for (var i = 0; i < 3; i++) ...[
          Container(
            height: 148,
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}
