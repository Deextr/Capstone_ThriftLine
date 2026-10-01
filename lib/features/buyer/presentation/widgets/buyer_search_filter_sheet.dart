import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../models/enums.dart';
import '../../data/catalog_search_query.dart';
import '../../models/buyer_search_filters.dart';

class BuyerSearchFilterSheet extends StatefulWidget {
  const BuyerSearchFilterSheet({
    super.key,
    required this.initial,
    required this.categories,
    required this.onApply,
    required this.onReset,
  });

  final BuyerSearchFilters initial;
  final List<BuyerCategoryOption> categories;
  final ValueChanged<BuyerSearchFilters> onApply;
  final VoidCallback onReset;

  static Future<void> show(
    BuildContext context, {
    required BuyerSearchFilters initial,
    required List<BuyerCategoryOption> categories,
    required ValueChanged<BuyerSearchFilters> onApply,
    required VoidCallback onReset,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BuyerSearchFilterSheet(
        initial: initial,
        categories: categories,
        onApply: onApply,
        onReset: onReset,
      ),
    );
  }

  @override
  State<BuyerSearchFilterSheet> createState() => _BuyerSearchFilterSheetState();
}

class _BuyerSearchFilterSheetState extends State<BuyerSearchFilterSheet> {
  late BuyerListingTypeFilter _listingType;
  late String? _categoryId;
  late ProductCondition? _condition;
  late BuyerSearchSort _sort;
  late TextEditingController _minPrice;
  late TextEditingController _maxPrice;

  @override
  void initState() {
    super.initState();
    _listingType = widget.initial.listingType;
    _categoryId = widget.initial.categoryId;
    _condition = widget.initial.condition == null
        ? null
        : ProductCondition.values.firstWhere(
            (c) => productConditionDbValue(c) == widget.initial.condition,
            orElse: () => ProductCondition.good,
          );
    _sort = widget.initial.sort;
    _minPrice = TextEditingController(
      text: widget.initial.minPrice?.toStringAsFixed(0) ?? '',
    );
    _maxPrice = TextEditingController(
      text: widget.initial.maxPrice?.toStringAsFixed(0) ?? '',
    );
  }

  @override
  void dispose() {
    _minPrice.dispose();
    _maxPrice.dispose();
    super.dispose();
  }

  double? _parsePrice(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    return double.tryParse(trimmed.replaceAll(',', ''));
  }

  BuyerSearchFilters _buildFilters() {
    return BuyerSearchFilters(
      categoryId: _categoryId,
      listingType: _listingType,
      condition: _condition == null
          ? null
          : productConditionDbValue(_condition!),
      minPrice: _parsePrice(_minPrice.text),
      maxPrice: _parsePrice(_maxPrice.text),
      sort: _sort,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  Text(
                    'Filters',
                    style: AppTypography.heading.copyWith(fontSize: 18),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      widget.onReset();
                      Navigator.pop(context);
                    },
                    child: const Text('Reset'),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionTitle('Listing type'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: BuyerListingTypeFilter.values.map((type) {
                        final label = switch (type) {
                          BuyerListingTypeFilter.all => 'All products',
                          BuyerListingTypeFilter.fixedPrice => 'Fixed price',
                          BuyerListingTypeFilter.auction => 'Auction / bidding',
                        };
                        return _ChoiceChip(
                          label: label,
                          selected: _listingType == type,
                          onTap: () => setState(() => _listingType = type),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),
                    _SectionTitle('Category'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _ChoiceChip(
                          label: 'All categories',
                          selected: _categoryId == null,
                          onTap: () => setState(() => _categoryId = null),
                        ),
                        ...widget.categories.map(
                          (c) => _ChoiceChip(
                            label: c.name,
                            selected: _categoryId == c.id,
                            onTap: () => setState(() => _categoryId = c.id),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _SectionTitle('Price range (₱)'),
                    Text(
                      'Auctions use current bid when listing type includes bidding.',
                      style: AppTypography.caption.copyWith(fontSize: 11),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _minPrice,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            decoration: InputDecoration(
                              hintText: 'Min',
                              filled: true,
                              fillColor: AppColors.surfaceVariant,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 10),
                          child: Text('—'),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _maxPrice,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            decoration: InputDecoration(
                              hintText: 'Max',
                              filled: true,
                              fillColor: AppColors.surfaceVariant,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _SectionTitle('Condition'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _ChoiceChip(
                          label: 'Any',
                          selected: _condition == null,
                          onTap: () => setState(() => _condition = null),
                        ),
                        ...ProductCondition.values.map(
                          (c) => _ChoiceChip(
                            label: c.label,
                            selected: _condition == c,
                            onTap: () => setState(() => _condition = c),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _SectionTitle('Sort by'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: BuyerSearchSort.values.map((sort) {
                        return _ChoiceChip(
                          label: sort.label,
                          selected: _sort == sort,
                          onTap: () => setState(() => _sort = sort),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () {
                      widget.onApply(_buildFilters());
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      'Apply filters',
                      style: AppTypography.subheading.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
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
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: AppTypography.subheading.copyWith(fontSize: 14)),
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      selectedColor: AppColors.primary.withValues(alpha: 0.14),
      labelStyle: AppTypography.caption.copyWith(
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        color: selected ? AppColors.primary : AppColors.textPrimary,
      ),
      side: BorderSide(
        color: selected
            ? AppColors.primary
            : AppColors.border.withValues(alpha: 0.7),
      ),
      onSelected: (_) => onTap(),
    );
  }
}
