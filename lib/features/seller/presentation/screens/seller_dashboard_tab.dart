import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../models/enums.dart';
import '../../../../models/looking_for_model.dart';
import '../../../../models/order_model.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../providers/notifications_provider.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../../buyer/controllers/looking_for_controller.dart';
import '../../../trust_safety/data/review_rules.dart';
import '../../controllers/seller_earnings_controller.dart';
import '../../controllers/seller_orders_controller.dart';
import '../widgets/seller_earnings_panel.dart';

class SellerDashboardTab extends StatelessWidget {
  const SellerDashboardTab({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final looking = context.watch<LookingForController>();
    final ordersCtrl = context.watch<SellerOrdersController>();
    final user = auth.user;
    final pending = ordersCtrl.pendingCount;
    final recentOrders = ordersCtrl.orders
        .where((order) => order.isSellerVisible)
        .take(3)
        .toList();
    final lookingForPosts = looking.posts.take(3).toList();

    return ColoredBox(
      color: AppColors.background,
      child: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          strokeWidth: 2.5,
          onRefresh: () async {
            await Future.wait([
              context.read<LookingForController>().refresh(),
              context.read<SellerOrdersController>().load(),
              context.read<SellerEarningsController>().load(),
            ]);
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // â”€â”€ Sticky top bar â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
              SliverToBoxAdapter(child: _TopBar(user: user)),

              SliverToBoxAdapter(
                child: SellerEarningsPanel(
                  pendingCount: pending,
                  ratingLabel: formatRatingAverage(
                    average: user?.rating,
                    count: user?.ratingCount ?? 0,
                    compact: true,
                  ),
                ),
              ),

              // Quick actions
              SliverToBoxAdapter(child: _QuickActionBar()),

              // Recent Orders
              SliverToBoxAdapter(
                child: _SectionLabel(title: 'Recent Orders', onTap: () {}),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _OrderTile(order: recentOrders[i]),
                    ),
                    childCount: recentOrders.length,
                  ),
                ),
              ),

              // â”€â”€ Looking For â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
              SliverToBoxAdapter(
                child: _SectionLabel(title: 'Buyers Looking For'),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _LookingForTile(post: lookingForPosts[i]),
                    ),
                    childCount: lookingForPosts.length,
                  ),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Top Bar
// =============================================================================

class _TopBar extends StatelessWidget {
  const _TopBar({required this.user});
  final dynamic user;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        children: [
          // Avatar
          ThriftAvatar(imageUrl: user?.avatarUrl ?? '', size: 42),
          const SizedBox(width: 12),
          // Name & greeting
          Expanded(
            child: Text(
              user?.shopName ?? user?.name ?? 'Seller',
              style: AppTypography.heading,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Notification icon
          Badge(
            isLabelVisible:
                context.watch<NotificationsProvider>().unreadCount > 0,
            label: Text(
              '${context.watch<NotificationsProvider>().unreadCount}',
            ),
            child: _IconBtn(
              icon: Icons.notifications_outlined,
              onTap: () => context.push(RouteNames.notifications),
            ),
          ),
          const SizedBox(width: 6),
          _IconBtn(
            icon: Icons.tune_rounded,
            onTap: () => showThriftSnackBar(context, 'Settings coming soon'),
          ),
        ],
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          border: Border.all(color: AppColors.border),
        ),
        child: Icon(icon, size: 20, color: AppColors.textPrimary),
      ),
    );
  }
}

// =============================================================================
// Quick Action Bar
// =============================================================================

class _QuickActionBar extends StatelessWidget {
  const _QuickActionBar();

  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.add_rounded, 'New Listing', AppColors.primary),
      (Icons.live_tv_rounded, 'Go Live', AppColors.error),
      (Icons.inventory_2_outlined, 'Orders', AppColors.secondary),
      (Icons.chat_bubble_outline_rounded, 'Messages', AppColors.info),
      (Icons.bar_chart_rounded, 'Analytics', AppColors.success),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Row(
        children: items.map((item) {
          final (icon, label, color) = item;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 2,
              ), // Slightly reduced horizontal padding to fit 5 items
              child: _ActionTile(
                icon: icon,
                label: label,
                color: color,
                onTap: () {
                  if (label == 'New Listing') {
                    context.push(RouteNames.addListing);
                  } else if (label == 'Messages') {
                    context.push(RouteNames.chat);
                  } else {
                    showThriftSnackBar(context, '$label coming soon');
                  }
                },
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: AppTypography.caption.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 11,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Section Label
// =============================================================================

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.title, this.onTap});
  final String title;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
      child: Row(
        children: [
          // Accent bar
          Container(
            width: 4,
            height: 18,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(title, style: AppTypography.subheading)),
          if (onTap != null)
            GestureDetector(
              onTap: onTap,
              child: Row(
                children: [
                  Text(
                    'See all',
                    style: AppTypography.label.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 11,
                    color: AppColors.primary,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// =============================================================================
// Order Tile
// =============================================================================

class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.order});
  final OrderModel order;

  @override
  Widget build(BuildContext context) {
    final isNew = order.isToShip;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          onTap: () => context.push('/seller-order/${order.id}'),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // Status indicator bar
                Container(
                  width: 4,
                  height: 46,
                  decoration: BoxDecoration(
                    color: isNew ? AppColors.warning : AppColors.success,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 14),
                // Icon
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                  ),
                  child: const Icon(
                    Icons.shopping_bag_outlined,
                    color: AppColors.textSecondary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.productTitle,
                        style: AppTypography.body.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(order.buyerName, style: AppTypography.caption),
                    ],
                  ),
                ),
                // Badge
                ThriftBadge(
                  label: orderStatusLabel(order.status),
                  variant: isNew ? BadgeVariant.warning : BadgeVariant.success,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Looking For Tile
// =============================================================================

class _LookingForTile extends StatelessWidget {
  const _LookingForTile({required this.post});
  final LookingForModel post;

  Future<void> _openPost(BuildContext context) async {
    await context.push(RouteNames.lookingForPost(post.id));
    if (!context.mounted) return;
    await context.read<LookingForController>().refresh();
  }

  Future<void> _iHaveThis(BuildContext context) async {
    final looking = context.read<LookingForController>();
    final result = await looking.sendIHaveThis(post);
    if (!context.mounted) return;
    if (!result.isOk) {
      showThriftSnackBar(context, result.error!, isError: true);
      return;
    }
    showThriftSnackBar(context, 'Message sent to the buyer.');
    if (result.conversationId != null) {
      context.push(RouteNames.chatThread(result.conversationId!));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          onTap: () => _openPost(context),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // Icon
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.secondary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                  ),
                  child: const Icon(
                    Icons.search_rounded,
                    color: AppColors.secondary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        post.title,
                        style: AppTypography.body.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Budget up to ${formatCurrency(post.budgetMax)}',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (context.read<LookingForController>().auth.user?.id !=
                    post.buyerId)
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(
                        AppConstants.radiusMd,
                      ),
                    ),
                    child: IconButton(
                      icon: const Icon(
                        Icons.reply_rounded,
                        color: AppColors.primaryDark,
                        size: 18,
                      ),
                      onPressed: () => _iHaveThis(context),
                      padding: const EdgeInsets.all(8),
                      constraints: const BoxConstraints(),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
