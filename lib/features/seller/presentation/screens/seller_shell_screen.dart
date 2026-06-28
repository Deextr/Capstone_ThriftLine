import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../providers/data_provider.dart';
import '../../../../widgets/curved_navigation_bar.dart';
import '../../../../widgets/thrift_widgets.dart';
import 'seller_dashboard_tab.dart';
import 'seller_listings_tab.dart';
import 'seller_orders_tab.dart';
import 'seller_profile_tab.dart';

class SellerShellScreen extends StatefulWidget {
  const SellerShellScreen({super.key});

  @override
  State<SellerShellScreen> createState() => _SellerShellScreenState();
}

class _SellerShellScreenState extends State<SellerShellScreen> {
  int _index = 0;

  static const _tabs = [
    SellerDashboardTab(),
    SellerListingsTab(),
    SellerOrdersTab(),
    _MessagesTab(),
    SellerProfileTab(),
  ];

  void _onTabChanged(int newIndex) {
    if (newIndex == _index) return;
    setState(() => _index = newIndex);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final data = context.watch<DataProvider>();
    final sellerId = auth.user?.id ?? 'seller_carla';
    final pending = data.pendingOrdersForSeller(sellerId);

    // Build nav items with dynamic badge for orders
    final navItems = [
      const CurvedNavItem(
        icon: Icons.bar_chart_outlined,
        activeIcon: Icons.bar_chart_rounded,
        label: 'Dashboard',
      ),
      const CurvedNavItem(
        icon: Icons.sell_outlined,
        activeIcon: Icons.sell_rounded,
        label: 'Listings',
      ),
      CurvedNavItem(
        icon: Icons.inventory_2_outlined,
        activeIcon: Icons.inventory_2_rounded,
        label: 'Orders',
        badge: pending > 0
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.error,
                  borderRadius: BorderRadius.circular(10),
                ),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                child: Text(
                  '$pending',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              )
            : null,
      ),
      const CurvedNavItem(
        icon: Icons.chat_bubble_outline_rounded,
        activeIcon: Icons.chat_bubble_rounded,
        label: 'Messages',
      ),
      const CurvedNavItem(
        icon: Icons.storefront_outlined,
        activeIcon: Icons.storefront_rounded,
        label: 'Profile',
      ),
    ];

    return Scaffold(
      extendBody: true,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, animation) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
        child: KeyedSubtree(
          key: ValueKey<int>(_index),
          child: _tabs[_index],
        ),
      ),
      bottomNavigationBar: CurvedNavigationBar(
        selectedIndex: _index,
        onTap: _onTabChanged,
        items: navItems,
      ),
    );
  }
}

class _MessagesTab extends StatelessWidget {
  const _MessagesTab();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: ThriftButton(
          label: 'Open Messages',
          expand: false,
          onPressed: () => context.push(RouteNames.chat),
        ),
      ),
    );
  }
}
