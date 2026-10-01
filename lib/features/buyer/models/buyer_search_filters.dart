enum BuyerListingTypeFilter { all, fixedPrice, auction }

enum BuyerSearchSort {
  relevance('Relevance'),
  newest('Most Recent'),
  priceLowHigh('Price: Low to High'),
  priceHighLow('Price: High to Low'),
  endingSoon('Ending Soon');

  const BuyerSearchSort(this.label);
  final String label;
}

class BuyerCategoryOption {
  const BuyerCategoryOption({required this.id, required this.name});

  final String id;
  final String name;
}

class BuyerSearchFilters {
  const BuyerSearchFilters({
    this.categoryId,
    this.listingType = BuyerListingTypeFilter.all,
    this.condition,
    this.minPrice,
    this.maxPrice,
    this.sort = BuyerSearchSort.relevance,
  });

  final String? categoryId;
  final BuyerListingTypeFilter listingType;
  final String? condition;
  final double? minPrice;
  final double? maxPrice;
  final BuyerSearchSort sort;

  static const cleared = BuyerSearchFilters();

  bool get hasPriceRange => minPrice != null || maxPrice != null;

  bool get hasNonDefaultSort => sort != BuyerSearchSort.relevance;

  bool get hasActiveFilters =>
      categoryId != null ||
      listingType != BuyerListingTypeFilter.all ||
      condition != null ||
      hasPriceRange ||
      hasNonDefaultSort;

  int get activeFilterCount {
    var count = 0;
    if (categoryId != null) count++;
    if (listingType != BuyerListingTypeFilter.all) count++;
    if (condition != null) count++;
    if (hasPriceRange) count++;
    if (hasNonDefaultSort) count++;
    return count;
  }

  BuyerSearchFilters copyWith({
    String? categoryId,
    bool clearCategoryId = false,
    BuyerListingTypeFilter? listingType,
    String? condition,
    bool clearCondition = false,
    double? minPrice,
    double? maxPrice,
    bool clearMinPrice = false,
    bool clearMaxPrice = false,
    BuyerSearchSort? sort,
  }) {
    return BuyerSearchFilters(
      categoryId: clearCategoryId ? null : (categoryId ?? this.categoryId),
      listingType: listingType ?? this.listingType,
      condition: clearCondition ? null : (condition ?? this.condition),
      minPrice: clearMinPrice ? null : (minPrice ?? this.minPrice),
      maxPrice: clearMaxPrice ? null : (maxPrice ?? this.maxPrice),
      sort: sort ?? this.sort,
    );
  }
}
