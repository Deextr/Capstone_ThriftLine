import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../providers/data_provider.dart';
import '../../../../widgets/empty_state.dart';
import '../../../../widgets/product_card.dart';

class SavedItemsScreen extends StatelessWidget {
  const SavedItemsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final saved = context.watch<DataProvider>().savedProducts;

    return Scaffold(
      appBar: AppBar(title: const Text('Saved Items'), leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop())),
      body: SafeArea(
        child: saved.isEmpty
            ? const EmptyState(icon: Icons.favorite_border, title: 'No saved items', message: 'Tap the heart on items you love!')
            : GridView.builder(
                padding: const EdgeInsets.all(AppConstants.spacingMd),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.62,
                ),
                itemCount: saved.length,
                itemBuilder: (_, i) => ProductCard(
                  product: saved[i],
                  onTap: () => context.push('/product/${saved[i].id}'),
                ),
              ),
      ),
    );
  }
}
