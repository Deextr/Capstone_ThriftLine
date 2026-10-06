import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../widgets/product_card.dart';
import '../../../../widgets/skeleton_widgets.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../controllers/buyer_search_controller.dart';
import '../../models/buyer_search_filters.dart';
import '../widgets/buyer_search_filter_sheet.dart';

class BuyerSearchTab extends StatefulWidget {
  const BuyerSearchTab({super.key});

  @override
  State<BuyerSearchTab> createState() => _BuyerSearchTabState();
}

class _BuyerSearchTabState extends State<BuyerSearchTab> {
  final _controller = TextEditingController();
  Timer? _debounceTimer;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onSearchChanged(String _) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 400), () {
      context.read<BuyerSearchController>().search(
        query: _controller.text,
        reset: true,
      );
    });
    setState(() {});
  }

  Future<void> _submitSearch() {
    return context.read<BuyerSearchController>().submitSearch(_controller.text);
  }

  void _runQuery(String query) {
    _controller.text = query;
    setState(() {});
    context.read<BuyerSearchController>().submitSearch(query);
  }

  @override
  Widget build(BuildContext context) {
    final search = context.watch<BuyerSearchController>();
    final query = _controller.text;
    final results = search.results;
    final loading = search.isLoading;
    final showResults = search.hasBrowseCriteria;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppConstants.spacingMd,
                AppConstants.spacingMd,
                AppConstants.spacingMd,
                8,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: ThriftTextField(
                      controller: _controller,
                      hint: 'Search vintage, streetwear, brands…',
                      icon: Icons.search_rounded,
                      autofocus: false,
                      onChanged: _onSearchChanged,
                      onSubmitted: (_) => _submitSearch(),
                      suffix: query.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () {
                                _controller.clear();
                                context.read<BuyerSearchController>().search(
                                  query: '',
                                  reset: true,
                                );
                                setState(() {});
                              },
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _FilterButton(
                    activeCount: search.filters.activeFilterCount,
                    onTap: () => BuyerSearchFilterSheet.show(
                      context,
                      initial: search.filters,
                      categories: search.categories,
                      onApply: search.applyFilters,
                      onReset: search.resetFilters,
                    ),
                  ),
                ],
              ),
            ),
            if (search.categories.isNotEmpty)
              SizedBox(
                height: 38,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    ThriftChip(
                      label: 'All',
                      selected: search.filters.categoryId == null,
                      onTap: () => search.setCategoryId(null),
                    ),
                    const SizedBox(width: 8),
                    ...search.categories.map(
                      (c) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ThriftChip(
                          label: c.name,
                          selected: search.filters.categoryId == c.id,
                          onTap: () => search.setCategoryId(c.id),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (search.filters.hasActiveFilters)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: _ActiveFilterChips(search: search),
              ),
            Expanded(
              child: !showResults
                  ? _discoveryState(search)
                  : loading && results.isEmpty
                  ? const SearchResultsGridSkeleton()
                  : results.isEmpty && search.errorMessage != null
                  ? _searchErrorState(search)
                  : results.isEmpty
                  ? _noResultsState(search)
                  : RefreshIndicator(
                      color: AppColors.primary,
                      onRefresh: _submitSearch,
                      child: NotificationListener<ScrollNotification>(
                        onNotification: (notification) {
                          if (notification.metrics.pixels >=
                              notification.metrics.maxScrollExtent - 240) {
                            search.loadMore();
                          }
                          return false;
                        },
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final textScale = MediaQuery.textScalerOf(
                              context,
                            ).scale(1);
                            return GridView.builder(
                              padding: const EdgeInsets.all(16),
                              gridDelegate: ProductCard.gridDelegateFor(
                                maxWidth: constraints.maxWidth,
                                compact: true,
                                textScale: textScale,
                              ),
                              itemCount:
                                  results.length +
                                  (search.isLoadingMore ? 2 : 0),
                              itemBuilder: (_, i) {
                                if (i >= results.length) {
                                  return const ProductCardSkeleton();
                                }
                                return ProductCard(
                                  product: results[i],
                                  compact: true,
                                  showCountdown: results[i].hasActiveBid,
                                  onTap: () =>
                                      context.push('/product/${results[i].id}'),
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _discoveryState(BuyerSearchController search) {
    if (search.isLoadingMeta) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Recent searches', style: AppTypography.subheading),
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
            contentPadding: EdgeInsets.zero,
            leading: const Icon(
              Icons.history_rounded,
              color: AppColors.textHint,
            ),
            title: Text(s, style: AppTypography.body),
            trailing: IconButton(
              icon: const Icon(Icons.close_rounded, size: 18),
              onPressed: () => search.removeRecentSearch(s),
            ),
            onTap: () => _runQuery(s),
          ),
        ),
        if (search.popularSearches.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('Popular searches', style: AppTypography.subheading),
          const SizedBox(height: 4),
          Text(
            'Trending on ThriftLine this week',
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: search.popularSearches
                .map(
                  (s) => ActionChip(
                    avatar: const Icon(
                      Icons.trending_up_rounded,
                      size: 16,
                      color: AppColors.primary,
                    ),
                    label: Text(s),
                    onPressed: () => _runQuery(s),
                  ),
                )
                .toList(),
          ),
        ],
      ],
    );
  }

  Widget _noResultsState(BuyerSearchController search) {
    final q = search.lastQuery.trim();
    final headline = q.isEmpty
        ? 'No products match your filters.'
        : 'No products found for “$q”.';
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 48),
        Icon(Icons.search_off_rounded, size: 48, color: AppColors.textHint),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            headline,
            textAlign: TextAlign.center,
            style: AppTypography.body.copyWith(color: AppColors.textSecondary),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            'Try different keywords, clear filters, or browse all categories.',
            textAlign: TextAlign.center,
            style: AppTypography.caption,
          ),
        ),
      ],
    );
  }

  Widget _searchErrorState(BuyerSearchController search) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 32),
      children: [
        const SizedBox(height: 48),
        const Icon(
          Icons.error_outline_rounded,
          size: 48,
          color: AppColors.error,
        ),
        const SizedBox(height: 12),
        Text(
          search.errorMessage ?? 'Search failed. Please try again.',
          textAlign: TextAlign.center,
          style: AppTypography.body.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 20),
        Center(
          child: ThriftButton(
            label: 'Retry',
            expand: false,
            onPressed: () => search.submitSearch(search.lastQuery),
          ),
        ),
      ],
    );
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.activeCount, required this.onTap});

  final int activeCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: activeCount > 0
          ? AppColors.primary.withValues(alpha: 0.12)
          : AppColors.surfaceVariant,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                Icons.tune_rounded,
                color: activeCount > 0
                    ? AppColors.primary
                    : AppColors.textPrimary,
              ),
              if (activeCount > 0)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$activeCount',
                      style: AppTypography.caption.copyWith(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActiveFilterChips extends StatelessWidget {
  const _ActiveFilterChips({required this.search});

  final BuyerSearchController search;

  @override
  Widget build(BuildContext context) {
    final filters = search.filters;
    final chips = <Widget>[];

    if (filters.listingType != BuyerListingTypeFilter.all) {
      final label = switch (filters.listingType) {
        BuyerListingTypeFilter.fixedPrice => 'Fixed price',
        BuyerListingTypeFilter.auction => 'Auction',
        BuyerListingTypeFilter.all => '',
      };
      chips.add(
        _RemovableChip(
          label: label,
          onRemove: () => search.applyFilters(
            filters.copyWith(listingType: BuyerListingTypeFilter.all),
          ),
        ),
      );
    }
    if (filters.condition != null) {
      chips.add(
        _RemovableChip(
          label: 'Condition',
          onRemove: () =>
              search.applyFilters(filters.copyWith(clearCondition: true)),
        ),
      );
    }
    if (filters.hasPriceRange) {
      chips.add(
        _RemovableChip(
          label: 'Price',
          onRemove: () => search.applyFilters(
            filters.copyWith(clearMinPrice: true, clearMaxPrice: true),
          ),
        ),
      );
    }
    if (filters.hasNonDefaultSort) {
      chips.add(
        _RemovableChip(
          label: filters.sort.label,
          onRemove: () => search.applyFilters(
            filters.copyWith(sort: BuyerSearchSort.relevance),
          ),
        ),
      );
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(spacing: 8, runSpacing: 6, children: chips),
    );
  }
}

class _RemovableChip extends StatelessWidget {
  const _RemovableChip({required this.label, required this.onRemove});

  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return InputChip(
      label: Text(label, style: AppTypography.caption),
      deleteIcon: const Icon(Icons.close_rounded, size: 16),
      onDeleted: onRemove,
      backgroundColor: AppColors.primary.withValues(alpha: 0.1),
      side: BorderSide(color: AppColors.primary.withValues(alpha: 0.25)),
    );
  }
}

class SearchScreen extends StatelessWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Search',
          style: AppTypography.heading.copyWith(fontSize: 18),
        ),
      ),
      body: const BuyerSearchTab(),
    );
  }
}
