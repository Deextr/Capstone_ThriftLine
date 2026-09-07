import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../models/enums.dart';
import '../../../../models/product_model.dart';
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
  Timer? _debounceTimer;

  List<ProductModel> _results = [];
  bool _loading = false;

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

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.isEmpty) {
      if (mounted) setState(() => _results = []);
      return;
    }

    if (mounted) setState(() => _loading = true);

    try {
      final supabase = context.read<SupabaseService>();
      var filterBuilder = supabase.client
          .from('products')
          .select('''
            *,
            seller:user_public_profiles (
              user_id,
              username,
              full_name,
              avatar,
              rating_average,
              trust_score,
              role
            ),
            images:product_images (
              image_url,
              is_primary,
              display_order
            ),
            category:categories (
              category_name
            )
          ''')
          .eq('status', 'active');

      if (query.isNotEmpty) {
        filterBuilder = filterBuilder.or(
          'name.ilike.%$query%,description.ilike.%$query%,brand.ilike.%$query%',
        );
      }

      final String orderColumn;
      final bool ascending;
      if (_sort == 'Price Low-High') {
        orderColumn = 'price';
        ascending = true;
      } else if (_sort == 'Price High-Low') {
        orderColumn = 'price';
        ascending = false;
      } else {
        orderColumn = 'created_at';
        ascending = false;
      }

      final rows = await filterBuilder
          .order(orderColumn, ascending: ascending)
          .limit(40) as List<dynamic>;
      var products = rows
          .map((r) => ProductModel.fromSupabase(r as Map<String, dynamic>))
          .where((p) => p.status == ProductStatus.active)
          .toList();

      if (_category != 'All') {
        products = products.where((p) {
          final catName = p.category.name.toLowerCase();
          return catName.contains(_category.toLowerCase());
        }).toList();
      }

      if (mounted) {
        setState(() {
          _results = products;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataProvider>();
    final query = _controller.text;

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
                              context, 'Voice search coming soon');
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
                children: [
                  'All',
                  'Tops',
                  'Bottoms',
                  'Shoes',
                  'Bags',
                  'Accessories'
                ]
                    .map((c) => ThriftChip(
                          label: c,
                          selected: _category == c,
                          onTap: () {
                            setState(() => _category = c);
                            _search();
                          },
                        ))
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
                    items: [
                      'Relevance',
                      'Price Low-High',
                      'Price High-Low',
                      'Newest',
                      'Ending Soon'
                    ]
                        .map((s) => DropdownMenuItem(
                            value: s,
                            child: Text(s, style: AppTypography.caption)))
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
                  ? _emptyState(data)
                  : _loading
                      ? const Center(
                          child: CircularProgressIndicator(
                              color: AppColors.primary),
                        )
                      : _results.isEmpty
                          ? Center(
                              child: Text(
                                'No products found.',
                                style: AppTypography.body.copyWith(
                                    color: AppColors.textSecondary),
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
                                itemCount: _results.length,
                                itemBuilder: (_, i) => ProductCard(
                                  product: _results[i],
                                  onTap: () {
                                    data.addRecentSearch(query);
                                    context.push('/product/${_results[i].id}');
                                  },
                                  onSellerTap: () => context.push(
                                      '/seller-profile/${_results[i].sellerUsername}'),
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
        title: const Text('Search'),
      ),
      body: const BuyerSearchTab(),
    );
  }
}
