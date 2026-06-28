import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/ai_search_parser.dart';
import '../../../../providers/data_provider.dart';
import '../../../../widgets/product_card.dart';
import '../../../../widgets/thrift_widgets.dart';

class BuyerSearchTab extends StatefulWidget {
  const BuyerSearchTab({super.key});

  @override
  State<BuyerSearchTab> createState() => _BuyerSearchTabState();
}

class _BuyerSearchTabState extends State<BuyerSearchTab> {
  final _controller = TextEditingController();
  String _category = 'All';
  String _sort = 'Relevance';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataProvider>();
    final query = _controller.text;
    final ai = query.isNotEmpty ? parseAiSearch(query) : null;
    final results = data.searchProducts(query, category: _category == 'All' ? null : _category, sort: _sort);

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppConstants.spacingMd),
              child: ThriftTextField(
                controller: _controller,
                hint: 'Search with AI...',
                icon: Icons.search,
                autofocus: false,
                onChanged: (_) => setState(() {}),
                suffix: query.isNotEmpty
                    ? IconButton(icon: const Icon(Icons.close), onPressed: () {
                        _controller.clear();
                        setState(() {});
                      })
                    : null,
              ),
            ),
            if (ai != null && query.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ThriftCard(
                  child: Text(aiUnderstandingText(ai), style: AppTypography.body.copyWith(color: AppColors.primaryDark)),
                ),
              ),
            const SizedBox(height: 8),
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: ['All', 'Tops', 'Bottoms', 'Shoes', 'Bags', 'Accessories'].map((c) => ThriftChip(
                  label: c,
                  selected: _category == c,
                  onTap: () => setState(() => _category = c),
                )).toList(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Text('Sort: ', style: AppTypography.caption),
                  DropdownButton<String>(
                    value: _sort,
                    underline: const SizedBox(),
                    items: ['Relevance', 'Price Low-High', 'Price High-Low', 'Newest', 'Ending Soon']
                        .map((s) => DropdownMenuItem(value: s, child: Text(s, style: AppTypography.caption)))
                        .toList(),
                    onChanged: (v) => setState(() => _sort = v!),
                  ),
                ],
              ),
            ),
            Expanded(
              child: query.isEmpty
                  ? _emptyState(data)
                  : RefreshIndicator(
                      onRefresh: () async => setState(() {}),
                      child: GridView.builder(
                        padding: const EdgeInsets.all(16),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.52,
                        ),
                        itemCount: results.length,
                        itemBuilder: (_, i) => ProductCard(
                          product: results[i],
                          onTap: () {
                            data.addRecentSearch(query);
                            context.push('/product/${results[i].id}');
                          },
                          onSellerTap: () => context.push('/seller-profile/${results[i].sellerUsername}'),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(DataProvider data) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Recent Searches', style: AppTypography.subheading),
        const SizedBox(height: 8),
        ...data.recentSearches.map((s) => ListTile(
          leading: const Icon(Icons.history, color: AppColors.textHint),
          title: Text(s, style: AppTypography.body),
          trailing: IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => data.removeRecentSearch(s),
          ),
          onTap: () {
            _controller.text = s;
            setState(() {});
          },
        )),
        const SizedBox(height: 24),
        Text('Popular Searches', style: AppTypography.subheading),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: data.popularSearches.map((s) => ActionChip(
            label: Text(s),
            onPressed: () {
              _controller.text = s;
              setState(() {});
            },
          )).toList(),
        ),
      ],
    );
  }
}

class SearchScreen extends StatelessWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
        title: const Text('AI Smart Search'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showThriftSnackBar(context, 'Voice search coming soon'),
        child: const Icon(Icons.mic),
      ),
      body: const BuyerSearchTab(),
    );
  }
}
