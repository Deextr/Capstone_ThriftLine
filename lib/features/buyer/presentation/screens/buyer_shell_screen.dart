import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';


import '../../../../core/routes/route_names.dart';
import '../../../../widgets/curved_navigation_bar.dart';
import '../../../../widgets/thrift_widgets.dart';
import 'buyer_bids_tab.dart';
import 'buyer_home_tab.dart';
import 'buyer_looking_for_tab.dart';
import 'buyer_profile_tab.dart';

class BuyerShellScreen extends StatefulWidget {
  const BuyerShellScreen({super.key});

  @override
  State<BuyerShellScreen> createState() => _BuyerShellScreenState();
}

class _BuyerShellScreenState extends State<BuyerShellScreen> {
  int _index = 0;


  static const _tabs = [
    BuyerHomeTab(),
    BuyerBidsTab(),
    BuyerLookingForTab(),
    _MessagesTab(),
    BuyerProfileTab(),
  ];

  static const _navItems = [
    CurvedNavItem(
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
      label: 'Home',
    ),
    CurvedNavItem(
      icon: Icons.gavel_outlined,
      activeIcon: Icons.gavel_rounded,
      label: 'Bids',
    ),
    CurvedNavItem(
      icon: Icons.bookmark_outline_rounded,
      activeIcon: Icons.bookmark_rounded,
      label: 'Looking',
    ),
    CurvedNavItem(
      icon: Icons.chat_bubble_outline_rounded,
      activeIcon: Icons.chat_bubble_rounded,
      label: 'Messages',
    ),
    CurvedNavItem(
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person_rounded,
      label: 'Profile',
    ),
  ];

  void _onTabChanged(int newIndex) {
    if (newIndex == _index) return;
    setState(() => _index = newIndex);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Use extendBody so the curved nav bar can overlap the body edge
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
        items: _navItems,
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
