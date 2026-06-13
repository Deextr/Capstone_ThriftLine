import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/routes/route_names.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../providers/data_provider.dart';
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

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final data = context.watch<DataProvider>();
    final sellerId = auth.user?.id ?? 'seller_carla';
    final pending = data.pendingOrdersForSeller(sellerId);

    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          SellerDashboardTab(),
          SellerListingsTab(),
          SellerOrdersTab(),
          _MessagesTab(),
          SellerProfileTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.bar_chart_outlined), selectedIcon: Icon(Icons.bar_chart), label: 'Dashboard'),
          const NavigationDestination(icon: Icon(Icons.sell_outlined), selectedIcon: Icon(Icons.sell), label: 'Listings'),
          NavigationDestination(
            icon: Badge(isLabelVisible: pending > 0, label: Text('$pending'), child: const Icon(Icons.inventory_2_outlined)),
            selectedIcon: Badge(isLabelVisible: pending > 0, label: Text('$pending'), child: const Icon(Icons.inventory_2)),
            label: 'Orders',
          ),
          const NavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat_bubble), label: 'Messages'),
          const NavigationDestination(icon: Icon(Icons.storefront_outlined), selectedIcon: Icon(Icons.storefront), label: 'Profile'),
        ],
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
