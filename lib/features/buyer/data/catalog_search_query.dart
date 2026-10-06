import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/enums.dart';
import '../../../models/product_model.dart';
import '../models/buyer_search_filters.dart';
import 'catalog_product_query.dart';
import 'home_feed_query.dart';

const catalogSearchPageSize = 40;

String? listingTypeDbValue(BuyerListingTypeFilter filter) {
  return switch (filter) {
    BuyerListingTypeFilter.all => null,
    BuyerListingTypeFilter.fixedPrice => 'fixed_price',
    BuyerListingTypeFilter.auction => 'auction',
  };
}

({String column, bool ascending}) catalogSearchOrder(BuyerSearchSort sort) {
  return switch (sort) {
    BuyerSearchSort.priceLowHigh => (column: 'price', ascending: true),
    BuyerSearchSort.priceHighLow => (column: 'price', ascending: false),
    BuyerSearchSort.newest ||
    BuyerSearchSort.relevance => (column: 'created_at', ascending: false),
    BuyerSearchSort.endingSoon => (column: 'created_at', ascending: false),
  };
}

bool passesClientPriceFilter(ProductModel product, BuyerSearchFilters filters) {
  final min = filters.minPrice;
  final max = filters.maxPrice;
  if (min == null && max == null) return true;
  final value = product.displayPrice;
  if (min != null && value < min) return false;
  if (max != null && value > max) return false;
  return true;
}

List<ProductModel> applySearchResultFilters(
  List<ProductModel> products,
  BuyerSearchFilters filters,
) {
  var list = products.where(isLiveBuyerHomeListing).toList();

  if (filters.sort == BuyerSearchSort.endingSoon) {
    list = list.where((p) => p.hasActiveBid).toList()
      ..sort(
        (a, b) => (a.bidEndTime ?? DateTime.now()).compareTo(
          b.bidEndTime ?? DateTime.now(),
        ),
      );
  }

  if (filters.hasPriceRange) {
    list = list.where((p) => passesClientPriceFilter(p, filters)).toList();
  }

  return list;
}

Future<List<BuyerCategoryOption>> fetchActiveCategories(
  SupabaseClient client,
) async {
  final rows = await client
      .from('categories')
      .select('category_id, category_name')
      .eq('is_active', true)
      .order('category_name');
  return (rows as List<dynamic>)
      .map((row) {
        final map = row as Map<String, dynamic>;
        final id = map['category_id'] as String?;
        final name = map['category_name'] as String?;
        if (id == null || name == null) return null;
        return BuyerCategoryOption(id: id, name: name);
      })
      .whereType<BuyerCategoryOption>()
      .toList();
}

Future<List<dynamic>> fetchCatalogSearchRows(
  SupabaseClient client, {
  required String sanitizedQuery,
  required BuyerSearchFilters filters,
  required int offset,
  int limit = catalogSearchPageSize,
}) async {
  final listingType = listingTypeDbValue(filters.listingType);
  final order = catalogSearchOrder(filters.sort);
  final textFilter = sanitizedQuery.isEmpty
      ? ''
      : catalogIlikeOrFilter(sanitizedQuery);

  Future<List<dynamic>> run(String select) async {
    var query = client.from('products').select(select).eq('status', 'active');

    if (listingType != null) {
      query = query.eq('listing_type', listingType);
    }
    if (filters.categoryId != null && filters.categoryId!.isNotEmpty) {
      query = query.eq('category_id', filters.categoryId!);
    }
    if (filters.condition != null && filters.condition!.isNotEmpty) {
      query = query.eq('condition', filters.condition!);
    }
    if (textFilter.isNotEmpty) {
      query = query.or(textFilter);
    }

    if (filters.minPrice != null &&
        filters.listingType == BuyerListingTypeFilter.fixedPrice) {
      query = query.gte('price', filters.minPrice!);
    }
    if (filters.maxPrice != null &&
        filters.listingType == BuyerListingTypeFilter.fixedPrice) {
      query = query.lte('price', filters.maxPrice!);
    }

    if (filters.sort == BuyerSearchSort.endingSoon) {
      query = query.eq('listing_type', 'auction');
    }

    dynamic ordered = query.order(order.column, ascending: order.ascending);
    return ordered.range(offset, offset + limit - 1);
  }

  return runProductCatalogSelect((select) => run(select));
}

String productConditionDbValue(ProductCondition condition) {
  return switch (condition) {
    ProductCondition.newWithTags => 'new',
    ProductCondition.likeNew => 'like_new',
    ProductCondition.good => 'good',
    ProductCondition.fair => 'fair',
    ProductCondition.poor => 'poor',
  };
}
