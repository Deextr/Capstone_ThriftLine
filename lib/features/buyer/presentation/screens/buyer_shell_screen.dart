import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routes/route_names.dart';
import '../../../../widgets/thrift_widgets.dart';
import 'buyer_bids_tab.dart';
import 'buyer_home_tab.dart';
import 'buyer_looking_for_tab.dart';
import 'buyer_profile_tab.dart';
import 'buyer_search_tab.dart';

class BuyerShellScreen extends StatefulWidget {
  const BuyerShellScreen({super.key});

  @override
  State<BuyerShellScreen> createState() => _BuyerShellScreenState();
}

class _BuyerShellScreenState extends State<BuyerShellScreen> {
  int _index = 0;

  static const _tabs = [
    BuyerHomeTab(),
    BuyerSearchTab(),
    BuyerBidsTab(),
    BuyerLookingForTab(),
    _MessagesTab(),
    BuyerProfileTab(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.search), selectedIcon: Icon(Icons.search), label: 'Search'),
          NavigationDestination(icon: Icon(Icons.gavel_outlined), selectedIcon: Icon(Icons.gavel), label: 'Bids'),
          NavigationDestination(icon: Icon(Icons.bookmark_outline), selectedIcon: Icon(Icons.bookmark), label: 'Looking'),
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat_bubble), label: 'Messages'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
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
