import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../widgets/curved_navigation_bar.dart';
import '../../../buyer/presentation/screens/buyer_looking_for_tab.dart';
import '../../../chat/controllers/chat_list_controller.dart';
import '../../../chat/presentation/widgets/chat_inbox_view.dart';
import '../../../profile/screens/seller_profile_tab.dart';
import '../../controllers/seller_orders_controller.dart';
import '../../data/seller_order_buckets.dart';
import 'seller_dashboard_tab.dart';
import 'seller_listings_tab.dart';
import 'seller_orders_tab.dart';

class SellerTabScope extends InheritedWidget {
  const SellerTabScope({
    required this.openTab,
    required super.child,
    super.key,
  });

  final void Function(int index, {SellerOrderBucket? ordersBucket}) openTab;

  static const int listings = 1;
  static const int looking = 2;
  static const int orders = 3;
  static const int messages = 4;

  static void open(
    BuildContext context,
    int index, {
    SellerOrderBucket? ordersBucket,
  }) {
    context.findAncestorWidgetOfExactType<SellerTabScope>()?.openTab(
      index,
      ordersBucket: ordersBucket,
    );
  }

  @override
  bool updateShouldNotify(SellerTabScope oldWidget) => false;
}

class SellerShellScreen extends StatefulWidget {
  const SellerShellScreen({super.key});

  @override
  State<SellerShellScreen> createState() => _SellerShellScreenState();
}

class _SellerShellScreenState extends State<SellerShellScreen> {
  int _index = 0;
  SellerOrderBucket _ordersBucket = SellerOrderBucket.toShip;
  late final Widget _messagesTab;

  @override
  void initState() {
    super.initState();
    _messagesTab = ChangeNotifierProvider(
      create: (context) => ChatListController(
        supabase: context.read<SupabaseService>(),
        auth: context.read<AuthProvider>(),
      ),
      child: const ChatInboxView(showHeader: true),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncTabFromRoute());
  }

  int? _tabIndexFromQuery(String? tab) => switch (tab) {
        'dashboard' => 0,
        'listings' => SellerTabScope.listings,
        'looking' => SellerTabScope.looking,
        'orders' => SellerTabScope.orders,
        'messages' => SellerTabScope.messages,
        'profile' => 5,
        _ => null,
      };

  void _syncTabFromRoute() {
    if (!mounted) return;
    final tab = GoRouterState.of(context).uri.queryParameters['tab'];
    final index = _tabIndexFromQuery(tab);
    if (index != null && index != _index) {
      _openTab(index);
    }
  }

  void _openTab(int index, {SellerOrderBucket? ordersBucket}) {
    final nextBucket = index == SellerTabScope.orders
        ? (ordersBucket ?? SellerOrderBucket.toShip)
        : _ordersBucket;
    if (index == _index && nextBucket == _ordersBucket) return;
    setState(() {
      _index = index;
      _ordersBucket = nextBucket;
    });
  }

  void _onTabChanged(int newIndex) {
    if (newIndex == _index) return;
    _openTab(
      newIndex,
      ordersBucket: newIndex == SellerTabScope.orders
          ? SellerOrderBucket.toShip
          : null,
    );
  }

  Widget _page(int index) {
    return switch (index) {
      0 => const SellerDashboardTab(),
      1 => const SellerListingsTab(),
      2 => const BuyerLookingForTab(sellerWorkspace: true),
      3 => SellerOrdersTab(initialBucket: _ordersBucket),
      4 => _messagesTab,
      _ => const SellerProfileTab(),
    };
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

    return SellerTabScope(
      openTab: _openTab,
      child: Scaffold(
        extendBody: true,
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, animation) {
            return FadeTransition(opacity: animation, child: child);
          },
          child: KeyedSubtree(
            key: ValueKey<int>(_index),
            child: _page(_index),
          ),
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
