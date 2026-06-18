import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/data/mock_data.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../features/auth/data/auth_service.dart';
import '../../../../models/enums.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../providers/data_provider.dart';
import '../../../../widgets/thrift_widgets.dart';

class SellerDashboardTab extends StatelessWidget {
  const SellerDashboardTab({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final data = context.watch<DataProvider>();
    final user = AuthService().getUserByUsername(auth.username ?? '');
    final sellerId = auth.user?.id ?? 'seller_carla';
    final listings = data.productsForSeller(auth.username ?? '');
    final pending = data.pendingOrdersForSeller(sellerId);
    final recentOrders = data.ordersForSeller(sellerId).take(3).toList();

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () async {},
        child: ListView(
          padding: const EdgeInsets.all(AppConstants.spacingMd),
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Welcome back, ${user?.shopName ?? ''}!',
                      style: AppTypography.heading.copyWith(color: Colors.white),
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.notifications_outlined, color: Colors.white),
                      onPressed: () => context.push(RouteNames.notifications),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 2.5,
              children: [
                _statCard(
                  'Total Sales',
                  formatCurrency(45200),
                  Icons.trending_up,
                  AppColors.success,
                ),
                _statCard(
                  'Active Listings',
                  '${listings.length}',
                  Icons.sell,
                  AppColors.primary,
                ),
                _statCard(
                  'Pending Orders',
                  '$pending',
                  Icons.pending_actions,
                  AppColors.secondary,
                ),
                _statCard(
                  'Rating',
                  '${user?.rating ?? 4.8} ⭐',
                  Icons.star,
                  AppColors.warning,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _action(
                  context,
                  Icons.add,
                  'Add Listing',
                  () => context.push(RouteNames.addListing),
                ),
                _action(context, Icons.inventory_2, 'Orders', () {}),
                _action(
                  context,
                  Icons.chat,
                  'Messages',
                  () => context.push(RouteNames.chat),
                ),
                _action(
                  context,
                  Icons.bar_chart,
                  'Analytics',
                  () => showThriftSnackBar(context, 'Analytics coming soon'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text('Sales (7 days)', style: AppTypography.subheading),
            const SizedBox(height: 8),
            SizedBox(
              height: 180,
              child: LineChart(
                LineChartData(
                  gridData: const FlGridData(show: false),
                  titlesData: const FlTitlesData(show: false),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: MockData.salesChartData
                          .asMap()
                          .entries
                          .map((e) => FlSpot(e.key.toDouble(), e.value / 100))
                          .toList(),
                      isCurved: true,
                      color: AppColors.primary,
                      barWidth: 3,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        color: AppColors.primaryLight.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text('Recent Orders', style: AppTypography.subheading),
            ...recentOrders.map(
              (o) => Padding(
                padding: const EdgeInsets.only(top: 8),
                child: ThriftCard(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              o.productTitle,
                              style: AppTypography.body.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(o.buyerName, style: AppTypography.caption),
                          ],
                        ),
                      ),
                      ThriftBadge(
                        label: orderStatusLabel(o.status),
                        variant: BadgeVariant.neutral,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text('Looking For Opportunities', style: AppTypography.subheading),
            ...data.lookingForPosts
                .take(3)
                .map(
                  (p) => Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: ThriftCard(
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              p.title,
                              style: AppTypography.body,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          ThriftButton(
                            label: 'Respond',
                            expand: false,
                            variant: ThriftButtonVariant.secondary,
                            onPressed: () =>
                                showThriftSnackBar(context, 'Response sent!'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _statCard(String title, String value, IconData icon, Color color) =>
      ThriftCard(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(value, style: AppTypography.body.copyWith(fontWeight: FontWeight.bold)),
                    Text(title, style: AppTypography.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  Widget _action(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onTap,
  ) => GestureDetector(
    onTap: onTap,
    child: Column(
      children: [
        CircleAvatar(
          backgroundColor: AppColors.primaryLight,
          child: Icon(icon, color: AppColors.primary),
        ),
        const SizedBox(height: 4),
        Text(label, style: AppTypography.caption),
      ],
    ),
  );
}
