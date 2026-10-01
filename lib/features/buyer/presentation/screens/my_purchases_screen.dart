import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../models/order_model.dart';
import '../../../../widgets/empty_state.dart';
import '../../../../widgets/skeleton_widgets.dart';
import '../../../trust_safety/data/review_rules.dart';
import '../../controllers/buyer_orders_controller.dart';
import '../../data/buyer_purchase_category.dart';
import '../widgets/awaiting_payment_tile.dart';
import '../widgets/my_purchase_order_card.dart';

class MyPurchasesScreen extends StatefulWidget {
  const MyPurchasesScreen({super.key, this.initialCategory});

  final BuyerPurchaseCategory? initialCategory;

  @override
  State<MyPurchasesScreen> createState() => _MyPurchasesScreenState();
}

class _MyPurchasesScreenState extends State<MyPurchasesScreen> {
  late BuyerPurchaseCategory _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialCategory ?? defaultPurchaseCategory();
  }

  @override
  void didUpdateWidget(covariant MyPurchasesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialCategory != null &&
        widget.initialCategory != oldWidget.initialCategory) {
      _selected = widget.initialCategory!;
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<BuyerOrdersController>();

    final counts = purchaseCategoryCounts(controller.orders);
    final visible = ordersForPurchaseCategory(controller.orders, _selected);
    final hasAny = controller.orders.any(orderIncludedInMyPurchases);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('My Purchases'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _CategoryTabs(
              selected: _selected,
              counts: counts,
              onSelected: (cat) => setState(() => _selected = cat),
            ),
            Expanded(
              child: _OrderList(
                controller: controller,
                category: _selected,
                orders: visible,
                hasAnyOrder: hasAny,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryTabs extends StatefulWidget {
  const _CategoryTabs({
    required this.selected,
    required this.counts,
    required this.onSelected,
  });

  final BuyerPurchaseCategory selected;
  final Map<BuyerPurchaseCategory, int> counts;
  final ValueChanged<BuyerPurchaseCategory> onSelected;

  @override
  State<_CategoryTabs> createState() => _CategoryTabsState();
}

class _CategoryTabsState extends State<_CategoryTabs> {
  final ScrollController _scrollController = ScrollController();
  final Map<BuyerPurchaseCategory, GlobalKey> _chipKeys = {
    for (final cat in BuyerPurchaseCategory.values) cat: GlobalKey(),
  };

  @override
  void didUpdateWidget(covariant _CategoryTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) {
      _scrollSelectedIntoView();
    }
  }

  @override
  void initState() {
    super.initState();
    _scrollSelectedIntoView();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollSelectedIntoView() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final key = _chipKeys[widget.selected];
      final context = key?.currentContext;
      if (context == null) return;
      Scrollable.ensureVisible(
        context,
        alignment: 0.5,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      child: SingleChildScrollView(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.spacingMd,
          vertical: 12,
        ),
        child: Row(
          children: [
            for (final cat in BuyerPurchaseCategory.values) ...[
              _TabChip(
                key: _chipKeys[cat],
                label: cat.label,
                count: _countForTab(cat),
                selected: widget.selected == cat,
                onTap: () => widget.onSelected(cat),
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }

  int _countForTab(BuyerPurchaseCategory cat) {
    if (cat == BuyerPurchaseCategory.all) {
      return widget.counts[BuyerPurchaseCategory.all] ?? 0;
    }
    return widget.counts[cat] ?? 0;
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    super.key,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? AppColors.primary.withValues(alpha: 0.14)
          : AppColors.surfaceVariant.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: selected
                ? Border.all(color: AppColors.primary.withValues(alpha: 0.35))
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: AppTypography.caption.copyWith(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? AppColors.primary : AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.primary : AppColors.textHint,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count',
                    style: AppTypography.caption.copyWith(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _OrderList extends StatelessWidget {
  const _OrderList({
    required this.controller,
    required this.category,
    required this.orders,
    required this.hasAnyOrder,
  });

  final BuyerOrdersController controller;
  final BuyerPurchaseCategory category;
  final List<OrderModel> orders;
  final bool hasAnyOrder;

  @override
  Widget build(BuildContext context) {
    if (controller.isLoading && controller.orders.isEmpty) {
      return ListView.separated(
        padding: const EdgeInsets.all(AppConstants.spacingMd),
        itemCount: 4,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, _) => const TrackOrderCardSkeleton(),
      );
    }
    if (controller.errorMessage != null && controller.orders.isEmpty) {
      return ErrorState(
        message:
            'Unable to load your purchases. Please check your connection and try again.',
        onRetry: controller.load,
      );
    }
    if (orders.isEmpty) {
      return EmptyState(
        icon: _emptyIcon(category),
        title: _emptyTitle(category),
        message: _emptyMessage(category, hasAnyOrder),
        actionLabel: hasAnyOrder ? null : 'Browse items',
        onAction: hasAnyOrder ? null : () => context.go(RouteNames.buyerHome),
      );
    }

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: controller.load,
      child: ListView.separated(
        padding: const EdgeInsets.all(AppConstants.spacingMd),
        itemCount: orders.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final order = orders[index];
          final orderCategory = buyerPurchaseCategory(order);
          if (orderCategory == BuyerPurchaseCategory.toPay) {
            return AwaitingPaymentTile(order: order);
          }
          if (orderCategory == BuyerPurchaseCategory.cancelled) {
            return MyPurchaseOrderCard(
              order: order,
              category: BuyerPurchaseCategory.cancelled,
            );
          }
          final review = controller.reviewFor(order.id);
          final action = reviewActionKind(review);
          return MyPurchaseOrderCard(
            order: order,
            category: category == BuyerPurchaseCategory.all
                ? orderCategory
                : category,
            reviewActionKind: orderCategory == BuyerPurchaseCategory.completed
                ? action
                : null,
            onReviewTap: () async {
              await context.push(RouteNames.leaveReviewFor(order.id));
              if (context.mounted) {
                await controller.load(showSpinner: false);
              }
            },
          );
        },
      ),
    );
  }

  IconData _emptyIcon(BuyerPurchaseCategory cat) => switch (cat) {
        BuyerPurchaseCategory.all => Icons.receipt_long_outlined,
        BuyerPurchaseCategory.toPay => Icons.payments_outlined,
        BuyerPurchaseCategory.paymentConfirmed => Icons.verified_outlined,
        BuyerPurchaseCategory.toReceive => Icons.local_shipping_outlined,
        BuyerPurchaseCategory.cancelled => Icons.cancel_outlined,
        BuyerPurchaseCategory.completed => Icons.check_circle_outline,
        BuyerPurchaseCategory.returnRefund => Icons.assignment_return_outlined,
      };

  String _emptyTitle(BuyerPurchaseCategory cat) => switch (cat) {
        BuyerPurchaseCategory.all => 'No purchases yet',
        BuyerPurchaseCategory.toPay => 'Nothing to pay',
        BuyerPurchaseCategory.paymentConfirmed => 'No orders preparing',
        BuyerPurchaseCategory.toReceive => 'Nothing on the way',
        BuyerPurchaseCategory.cancelled => 'No cancelled wins',
        BuyerPurchaseCategory.completed => 'No completed orders',
        BuyerPurchaseCategory.returnRefund => 'No returns or refunds',
      };

  String _emptyMessage(BuyerPurchaseCategory cat, bool hasAny) {
    if (!hasAny) {
      return 'When you buy or win an auction, your orders will show up here.';
    }
    return switch (cat) {
      BuyerPurchaseCategory.all => 'Orders in other stages appear when you shop.',
      BuyerPurchaseCategory.toPay =>
        'Auction wins that need payment will appear in this tab.',
      BuyerPurchaseCategory.paymentConfirmed =>
        'Paid orders being prepared show here until they are out for delivery.',
      BuyerPurchaseCategory.toReceive =>
        'Orders on the way or awaiting your confirmation appear here.',
      BuyerPurchaseCategory.cancelled =>
        'Expired auction payment windows appear here.',
      BuyerPurchaseCategory.returnRefund =>
        'Orders with an open dispute or return show here.',
      _ => 'Try another tab to find your order.',
    };
  }
}
