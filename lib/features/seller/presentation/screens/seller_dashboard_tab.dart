import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../features/auth/domain/auth_user.dart';
import '../../../../models/looking_for_model.dart';
import '../../../../models/order_model.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../providers/notifications_provider.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../../buyer/controllers/looking_for_controller.dart';
import '../../controllers/seller_earnings_controller.dart';
import '../../controllers/seller_orders_controller.dart';
import '../../data/seller_order_buckets.dart';
import '../widgets/seller_earnings_panel.dart';
import 'seller_shell_screen.dart';

class SellerDashboardTab extends StatelessWidget {
  const SellerDashboardTab({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final looking = context.watch<LookingForController>();
    final ordersCtrl = context.watch<SellerOrdersController>();
    final earningsCtrl = context.watch<SellerEarningsController>();
    final unread = context.watch<NotificationsProvider>().unreadCount;
    final user = auth.user;

    final snapshot = earningsCtrl.snapshot;
    final listingsCount = snapshot == null ? '–' : '${snapshot.listingCount}';
    final ordersKnown = !ordersCtrl.isLoading || ordersCtrl.orders.isNotEmpty;
    final toShip = ordersCtrl.countIn(SellerOrderBucket.toShip);
    final shipped = ordersCtrl.countIn(SellerOrderBucket.shipped);
    final recentOrders = ordersCtrl.orders
        .where((order) => order.isSellerVisible)
        .take(2)
        .toList();
    final requests = looking.browsePosts.take(2).toList();

    return ColoredBox(
      color: AppColors.background,
      child: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          strokeWidth: 2.5,
          onRefresh: () async {
            await Future.wait([
              context.read<AuthProvider>().reloadUser(),
              context.read<LookingForController>().refresh(),
              context.read<SellerOrdersController>().load(),
              context.read<SellerEarningsController>().load(),
            ]);
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: _ShopHeader(unread: unread)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: SellerEarningsPanel(
                    pendingLabel: ordersKnown ? '$toShip' : '–',
                    ratingLabel: _ratingLabel(user),
                    onListings: () =>
                        SellerTabScope.open(context, SellerTabScope.listings),
                    onPending: () => SellerTabScope.open(
                      context,
                      SellerTabScope.orders,
                      ordersBucket: SellerOrderBucket.toShip,
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: _OrdersGlance(
                  toShipLabel: ordersKnown ? '$toShip' : '–',
                  shippedLabel: ordersKnown ? '$shipped' : '–',
                  emphasizeToShip: ordersKnown && toShip > 0,
                ),
              ),
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, 20, 16, 0),
                  child: SellerEarningsFollowup(),
                ),
              ),
              SliverToBoxAdapter(
                child: _YourShopSection(
                  listingCount: listingsCount,
                  ratingSummary: _ratingSummary(user),
                  onRatingTap:
                      user?.username != null && user!.username.isNotEmpty
                          ? () => context.push(
                                RouteNames.sellerProfile.replaceFirst(
                                  ':username',
                                  user.username,
                                ),
                              )
                          : null,
                ),
              ),
              SliverToBoxAdapter(
                child: _SectionLabel(
                  title: 'Recent sales',
                  action: recentOrders.isEmpty ? null : 'View orders',
                  onTap: recentOrders.isEmpty
                      ? null
                      : () =>
                            SellerTabScope.open(context, SellerTabScope.orders),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList.list(
                  children: [
                    if (!ordersKnown)
                      Text(
                        'Loading sales…',
                        style: AppTypography.body.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      )
                    else if (recentOrders.isEmpty)
                      Text(
                        'No sales yet.',
                        style: AppTypography.body.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      )
                    else
                      for (var i = 0; i < recentOrders.length; i++) ...[
                        if (i > 0) const SizedBox(height: 10),
                        _OrderTile(order: recentOrders[i]),
                      ],
                  ],
                ),
              ),
              SliverToBoxAdapter(
                child: _SectionLabel(
                  title: 'Buyers looking for',
                  action: 'See all',
                  onTap: () =>
                      SellerTabScope.open(context, SellerTabScope.looking),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                sliver: SliverList.list(
                  children: [
                    if (looking.isLoading && looking.posts.isEmpty)
                      Text(
                        'Loading requests…',
                        style: AppTypography.body.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      )
                    else if (requests.isEmpty)
                      Text(
                        'No requests right now.',
                        style: AppTypography.body.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      )
                    else
                      for (var i = 0; i < requests.length; i++) ...[
                        if (i > 0) const SizedBox(height: 10),
                        _LookingForTile(post: requests[i], myId: user?.id),
                      ],
                  ],
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 96)),
            ],
          ),
        ),
      ),
    );
  }
}

String _ratingLabel(AuthUser? user) {
  final rating = user?.rating;
  final count = user?.ratingCount ?? 0;
  if (rating == null || count <= 0) return '–';
  return rating.toStringAsFixed(1);
}

String _ratingSummary(AuthUser? user) {
  final rating = user?.rating;
  final count = user?.ratingCount ?? 0;
  if (rating == null || count <= 0) return 'No reviews yet';
  final reviewPlural = count == 1 ? '1 review' : '$count reviews';
  return '${rating.toStringAsFixed(1)} · $reviewPlural';
}

String _greetingText(AuthUser? user) {
  final hour = DateTime.now().hour;
  final timeOfDay = hour < 12
      ? 'Good morning'
      : hour < 18
      ? 'Good afternoon'
      : 'Good evening';
  final name = shortPersonName(user?.name ?? '');
  if (name.isNotEmpty) {
    return '$timeOfDay, $name';
  }
  return 'Your shop at a glance';
}

class _ShopHeader extends StatelessWidget {
  const _ShopHeader({required this.unread});

  final int unread;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final shopName =
        auth.displayName ?? user?.shopName ?? user?.name ?? 'Your shop';
    final greeting = _greetingText(user);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 6, 0),
      child: Row(
        children: [
          ThriftAvatar(
            key: ValueKey('seller-dash-${auth.activeAvatarUrl}'),
            imageUrl: auth.activeAvatarUrl,
            name: shopName,
            size: 40,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  greeting,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  shopName,
                  style: AppTypography.heading.copyWith(fontSize: 18),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'List an item',
            onPressed: () => context.push(RouteNames.addListing),
            icon: const Icon(Icons.add_rounded),
            color: AppColors.primaryDark,
          ),
          IconButton(
            tooltip: unread > 0
                ? 'Notifications, $unread unread'
                : 'Notifications',
            onPressed: () => context.push(RouteNames.notifications),
            icon: Badge(
              isLabelVisible: unread > 0,
              label: Text('$unread'),
              child: const Icon(Icons.notifications_outlined),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrdersGlance extends StatelessWidget {
  const _OrdersGlance({
    required this.toShipLabel,
    required this.shippedLabel,
    required this.emphasizeToShip,
  });

  final String toShipLabel;
  final String shippedLabel;
  final bool emphasizeToShip;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Orders', style: AppTypography.subheading)),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primaryDark,
                  minimumSize: const Size(44, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => SellerTabScope.open(
                  context,
                  SellerTabScope.orders,
                  ordersBucket: SellerOrderBucket.toShip,
                ),
                child: const Text('View orders'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppConstants.radiusLg),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                _OrderActionLine(
                  icon: Icons.local_shipping_outlined,
                  label: 'To ship',
                  count: toShipLabel,
                  badgeAlert: emphasizeToShip,
                  onTap: () => SellerTabScope.open(
                    context,
                    SellerTabScope.orders,
                    ordersBucket: SellerOrderBucket.toShip,
                  ),
                ),
                const Divider(height: 1, color: AppColors.border),
                _OrderActionLine(
                  icon: Icons.outbox_outlined,
                  label: 'Shipped',
                  count: shippedLabel,
                  badgeAlert: false,
                  onTap: () => SellerTabScope.open(
                    context,
                    SellerTabScope.orders,
                    ordersBucket: SellerOrderBucket.shipped,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderActionLine extends StatelessWidget {
  const _OrderActionLine({
    required this.icon,
    required this.label,
    required this.count,
    required this.badgeAlert,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String count;
  final bool badgeAlert;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$label $count',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: badgeAlert
                      ? AppColors.warning
                      : AppColors.textSecondary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: AppTypography.body.copyWith(
                      fontWeight: badgeAlert
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ),
                if (badgeAlert)
                  Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      count,
                      style: AppTypography.caption.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.warning,
                      ),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text(
                      count,
                      style: AppTypography.body.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: AppColors.textHint,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _YourShopSection extends StatelessWidget {
  const _YourShopSection({
    required this.listingCount,
    required this.ratingSummary,
    this.onRatingTap,
  });

  final String listingCount;
  final String ratingSummary;
  final VoidCallback? onRatingTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Your shop', style: AppTypography.subheading),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primaryDark,
                  minimumSize: const Size(44, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () =>
                    SellerTabScope.open(context, SellerTabScope.listings),
                child: const Text('Manage listings'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppConstants.radiusLg),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                _ShopInfoLine(
                  icon: Icons.storefront_outlined,
                  label: 'Active listings',
                  value: listingCount,
                  onTap: () =>
                      SellerTabScope.open(context, SellerTabScope.listings),
                ),
                const Divider(height: 1, color: AppColors.border),
                _ShopInfoLine(
                  icon: Icons.star_rounded,
                  iconColor: AppColors.warning,
                  label: 'Seller rating',
                  value: ratingSummary,
                  onTap: onRatingTap,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ShopInfoLine extends StatelessWidget {
  const _ShopInfoLine({
    required this.icon,
    this.iconColor,
    required this.label,
    required this.value,
    this.onTap,
  });

  final IconData icon;
  final Color? iconColor;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 20, color: iconColor ?? AppColors.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: AppTypography.body.copyWith(fontWeight: FontWeight.w500),
              ),
            ),
            Text(
              value,
              style: AppTypography.body.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: AppColors.textHint,
              ),
            ],
          ],
        ),
      ),
    );

    if (onTap == null) return row;
    return InkWell(
      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      onTap: onTap,
      child: row,
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.title, this.action, this.onTap});

  final String title;
  final String? action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 8),
      child: Row(
        children: [
          Expanded(child: Text(title, style: AppTypography.subheading)),
          if (onTap != null && action != null)
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primaryDark,
                minimumSize: const Size(44, 36),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: onTap,
              child: Text(action!),
            ),
        ],
      ),
    );
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.order});

  final OrderModel order;

  @override
  Widget build(BuildContext context) {
    final chip = sellerOrderChip(order);
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        side: const BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        onTap: () => context.push('/seller-order/${order.id}'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
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
                    const SizedBox(height: 2),
                    Text(
                      shortPersonName(order.buyerName),
                      style: AppTypography.caption,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                chip.label,
                style: AppTypography.caption.copyWith(
                  color: chip.variant == BadgeVariant.primary
                      ? AppColors.primaryDark
                      : AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LookingForTile extends StatelessWidget {
  const _LookingForTile({required this.post, required this.myId});

  final LookingForModel post;
  final String? myId;

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
    final canReply = myId != null && myId != post.buyerId;
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        side: const BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        onTap: () => _openPost(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            children: [
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
                    const SizedBox(height: 2),
                    Text(
                      'Up to ${formatCurrency(post.budgetMax)}',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.primaryDark,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (canReply)
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primaryDark,
                    minimumSize: const Size(44, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => _iHaveThis(context),
                  child: const Text('I have this'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
