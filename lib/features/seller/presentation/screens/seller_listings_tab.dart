import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../models/enums.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../providers/data_provider.dart';
import '../../../../widgets/product_card.dart';
import '../../../../widgets/thrift_widgets.dart';

class SellerListingsTab extends StatefulWidget {
  const SellerListingsTab({super.key});

  @override
  State<SellerListingsTab> createState() => _SellerListingsTabState();
}

class _SellerListingsTabState extends State<SellerListingsTab> with SingleTickerProviderStateMixin {
  late TabController _tab;
  bool _isGrid = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final data = context.watch<DataProvider>();
    final products = data.productsForSeller(auth.username ?? '');

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppConstants.spacingMd),
              child: Row(
                children: [
                  Expanded(child: Text('My Listings', style: AppTypography.heading)),
                  IconButton(icon: Icon(_isGrid ? Icons.view_list : Icons.grid_view), onPressed: () => setState(() => _isGrid = !_isGrid)),
                ],
              ),
            ),
            TabBar(
              controller: _tab,
              labelColor: AppColors.primary,
              tabs: const [Tab(text: 'Active'), Tab(text: 'Sold'), Tab(text: 'Drafts')],
            ),
            Expanded(
              child: TabBarView(
                controller: _tab,
                children: [
                  _buildList(products.where((p) => p.status == ProductStatus.active).toList()),
                  _buildList(products.where((p) => p.status == ProductStatus.sold).toList()),
                  _buildList(products.where((p) => p.status == ProductStatus.draft).toList()),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 72.0), // Offset to float above curved bottom nav
        child: FloatingActionButton(
          onPressed: () => context.push(RouteNames.addListing),
          backgroundColor: AppColors.primary,
          child: const Icon(Icons.add, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildList(List products) {
    if (products.isEmpty) {
      return const Center(child: Text('No listings'));
    }
    return RefreshIndicator(
      onRefresh: () async => setState(() {}),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: products.length,
        itemBuilder: (_, i) {
          final p = products[i];
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: ThriftCard(
              child: Row(
                children: [
                  Expanded(child: ProductCard(product: p, variant: ProductCardVariant.list)),
                  PopupMenuButton(
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'edit', child: Text('Edit')),
                      const PopupMenuItem(value: 'pause', child: Text('Pause')),
                      const PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                    onSelected: (v) => showThriftSnackBar(context, '$v action'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
