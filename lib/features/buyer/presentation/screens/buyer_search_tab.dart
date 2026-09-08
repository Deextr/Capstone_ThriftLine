import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../widgets/product_card.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../controllers/buyer_search_controller.dart';

class BuyerSearchTab extends StatefulWidget {
  const BuyerSearchTab({super.key});

  @override
  State<BuyerSearchTab> createState() => _BuyerSearchTabState();
}

class _BuyerSearchTabState extends State<BuyerSearchTab> {
  final _controller = TextEditingController();
  String _category = 'All';
  String _sort = 'Relevance';
  Timer? _debounceTimer;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onSearchChanged(String _) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), _search);
    setState(() {});
  }

  Future<void> _search() {
    return context.read<BuyerSearchController>().search(
      query: _controller.text,
      categoryLabel: _category,
      sort: _sort,
    );
  }

  @override
  Widget build(BuildContext context) {
    final search = context.watch<BuyerSearchController>();
    final query = _controller.text;
    final results = search.results;
    final loading = search.isLoading;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppConstants.spacingMd),
              child: ThriftTextField(
                controller: _controller,
                hint: 'Search vintage, streetwear...',
                icon: Icons.search,
                autofocus: false,
                onChanged: _onSearchChanged,
                suffix: query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _controller.clear();
                          _search();
                        },
                      )
                    : IconButton(
                        icon: const Icon(Icons.mic),
                        onPressed: () {
                          showThriftSnackBar(
                            context,
                            'Voice search coming soon',
                          );
                        },
                      ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children:
                    ['All', 'Tops', 'Bottoms', 'Shoes', 'Bags', 'Accessories']
                        .map(
                          (c) => ThriftChip(
                            label: c,
                            selected: _category == c,
                            onTap: () {
                              setState(() => _category = c);
                              _search();
                            },
                          ),
                        )
                        .toList(),
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
                    items:
                        [
                              'Relevance',
                              'Price Low-High',
                              'Price High-Low',
                              'Newest',
                              'Ending Soon',
                            ]
                            .map(
                              (s) => DropdownMenuItem(
                                value: s,
                                child: Text(s, style: AppTypography.caption),
                              ),
                            )
                            .toList(),
                    onChanged: (v) {
                      setState(() => _sort = v!);
                      _search();
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: query.isEmpty
                  ? _emptyState(search)
                  : loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    )
                  : results.isEmpty
                  ? Center(
                      child: Text(
                        search.errorMessage ?? 'No products found.',
                        style: AppTypography.body.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _search,
                      child: GridView.builder(
                        padding: const EdgeInsets.all(16),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                              childAspectRatio: 0.65,
                            ),
                        itemCount: results.length,
                        itemBuilder: (_, i) => ProductCard(
                          product: results[i],
                          onTap: () =>
                              context.push('/product/${results[i].id}'),
                          onSellerTap: () => context.push(
                            '/seller-profile/${results[i].sellerUsername}',
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(BuyerSearchController search) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Recent Searches', style: AppTypography.subheading),
        const SizedBox(height: 8),
        if (search.recentSearches.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Searches you run will show up here.',
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ...search.recentSearches.map(
          (s) => ListTile(
            leading: const Icon(Icons.history, color: AppColors.textHint),
            title: Text(s, style: AppTypography.body),
            trailing: IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => search.removeRecentSearch(s),
            ),
            onTap: () {
              _controller.text = s;
              setState(() {});
              _search();
            },
          ),
        ),
        const SizedBox(height: 24),
        Text('Popular Searches', style: AppTypography.subheading),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: search.popularSearches
              .map(
                (s) => ActionChip(
                  label: Text(s),
                  onPressed: () {
                    _controller.text = s;
                    setState(() {});
                    _search();
                  },
                ),
              )
              .toList(),
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: const Text('Search'),
      ),
      body: const BuyerSearchTab(),
    );
  }
}
