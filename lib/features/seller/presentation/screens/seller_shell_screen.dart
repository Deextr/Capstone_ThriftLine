import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../widgets/curved_navigation_bar.dart';
import '../../../buyer/controllers/looking_for_controller.dart';
import '../../../buyer/presentation/screens/buyer_looking_for_tab.dart';
import '../../../chat/controllers/chat_list_controller.dart';
import '../../../chat/presentation/widgets/chat_inbox_view.dart';
import '../../../profile/screens/seller_profile_tab.dart';
import '../../controllers/seller_orders_controller.dart';
import 'seller_dashboard_tab.dart';
import 'seller_listings_tab.dart';
import 'seller_orders_tab.dart';

class SellerShellScreen extends StatefulWidget {
  const SellerShellScreen({super.key});

  @override
  State<SellerShellScreen> createState() => _SellerShellScreenState();
}

class _SellerShellScreenState extends State<SellerShellScreen> {
  int _index = 0;
  late final List<Widget> _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = [
      const SellerDashboardTab(),
      const SellerListingsTab(),
      const BuyerLookingForTab(sellerWorkspace: true),
      const SellerOrdersTab(),
      ChangeNotifierProvider(
        create: (context) => ChatListController(
          supabase: context.read<SupabaseService>(),
          auth: context.read<AuthProvider>(),
        ),
        child: const ChatInboxView(showHeader: true),
      ),
      const SellerProfileTab(),
    ];
  }

  void _onTabChanged(int newIndex) {
    if (newIndex == _index) return;
    setState(() => _index = newIndex);
  }

  @override
  Widget build(BuildContext context) {
    final pending = context.watch<SellerOrdersController>().pendingCount;

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
      const CurvedNavItem(
        icon: Icons.bookmark_outline_rounded,
        activeIcon: Icons.bookmark_rounded,
        label: 'Looking',
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

    return ChangeNotifierProvider(
      create: (context) => LookingForController(
        supabase: context.read<SupabaseService>(),
        auth: context.read<AuthProvider>(),
      ),
      child: Scaffold(
        extendBody: true,
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, animation) {
            return FadeTransition(opacity: animation, child: child);
          },
          child: KeyedSubtree(key: ValueKey<int>(_index), child: _tabs[_index]),
        ),
        bottomNavigationBar: CurvedNavigationBar(
          selectedIndex: _index,
          onTap: _onTabChanged,
          items: navItems,
        ),
      ),
    );
  }
}
