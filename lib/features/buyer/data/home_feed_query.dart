import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/enums.dart';
import '../../../models/product_model.dart';
import '../../../models/seller_profile.dart';
import 'catalog_product_query.dart';

class HomeFeedSection<T> {
  const HomeFeedSection({
    this.items = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  final List<T> items;
  final bool isLoading;
  final String? errorMessage;

  bool get hasError => errorMessage != null;
  bool get isEmpty => !isLoading && errorMessage == null && items.isEmpty;

  HomeFeedSection<T> copyWith({
    List<T>? items,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
  }) {
    return HomeFeedSection<T>(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

bool isHomeOfflineError(Object error) {
  final text = error.toString().toLowerCase();
  return text.contains('socket') ||
      text.contains('host lookup') ||
      text.contains('network') ||
      text.contains('connection') ||
      text.contains('offline') ||
      text.contains('timed out') ||
      text.contains('failed host');
}

/// Ended auctions stay off the buyer home feed.
bool isLiveBuyerHomeListing(ProductModel p) {
  if (p.status != ProductStatus.active) return false;
  if (p.sellingType == SellingType.auction) return p.hasActiveBid;
  return true;
}

Future<List<dynamic>> fetchCatalogProductRows(
  SupabaseClient client, {
  required int limit,
  int offset = 0,
  String? listingType,
  List<String>? productIds,
  String orderColumn = 'created_at',
  bool ascending = false,
}) async {
  if (productIds != null && productIds.isEmpty) return const [];

  Future<List<dynamic>> run(String select, String order) {
    var query = client.from('products').select(select).eq('status', 'active');
    if (listingType != null) {
      query = query.eq('listing_type', listingType);
    }
    if (productIds != null) {
      query = query.inFilter('product_id', productIds);
    }
    final ordered = query
        .order(order, ascending: ascending)
        .order('product_id', ascending: true);
    if (offset <= 0) {
      return ordered.limit(limit);
    }
    return ordered.range(offset, offset + limit - 1);
  }

  try {
    return await run(productCatalogSelect, orderColumn);
  } catch (e) {
    debugPrint('home feed catalog ($orderColumn) failed ($e); retrying');
    try {
      if (orderColumn != 'created_at') {
        return await run(productCatalogSelect, 'created_at');
      }
    } catch (_) {}
    try {
      return await run(productCatalogSelectWithoutAuctions, 'created_at');
    } catch (e2) {
      debugPrint('home feed catalog retry failed ($e2)');
      rethrow;
    }
  }
}

Future<List<String>> fetchEndingSoonProductIds(
  SupabaseClient client, {
  int limit = 12,
}) async {
  final now = DateTime.now().toUtc().toIso8601String();
  final rows = await client
      .from('auctions')
      .select('product_id, ends_at')
      .eq('status', 'active')
      .gt('ends_at', now)
      .order('ends_at', ascending: true)
      .limit(limit);
  final ids = <String>[];
  for (final row in rows as List<dynamic>) {
    if (row is! Map<String, dynamic>) continue;
    final id = row['product_id'] as String?;
    if (id != null && id.isNotEmpty && !ids.contains(id)) ids.add(id);
  }
  return ids;
}

Future<Map<String, int>> fetchProductCartCounts(
  SupabaseClient client,
  Iterable<String> productIds,
) async {
  final ids = productIds.where((id) => id.isNotEmpty).toSet().toList();
  if (ids.isEmpty) return const {};
  try {
    final res = await client.rpc(
      'product_cart_counts',
      params: {'p_product_ids': ids},
    );
    final map = <String, int>{};
    if (res is List) {
      for (final row in res) {
        if (row is! Map) continue;
        final id = row['product_id'] as String?;
        final count = (row['cart_count'] as num?)?.toInt() ?? 0;
        if (id != null && count > 0) map[id] = count;
      }
    }
    return map;
  } catch (e) {
    debugPrint('fetchProductCartCounts: $e');
    return const {};
  }
}

List<ProductModel> sortProductsByIdOrder(
  List<ProductModel> products,
  List<String> orderedIds,
) {
  final byId = {for (final p in products) p.id: p};
  return [
    for (final id in orderedIds)
      if (byId[id] != null) byId[id]!,
  ];
}

Map<String, dynamic> productToCacheRow(ProductModel p) {
  return {
    'product_id': p.id,
    'seller_id': p.sellerId,
    'name': p.title,
    'description': p.description,
    'price': p.price,
    'listing_type': p.sellingType == SellingType.auction
        ? 'auction'
        : 'fixed_price',
    'status': 'active',
    'brand': p.brand,
    'location': p.location,
    'created_at': p.createdAt.toIso8601String(),
    'views': p.viewCount,
    'images': [
      for (var i = 0; i < p.imageUrls.length; i++)
        {'image_url': p.imageUrls[i], 'is_primary': i == 0, 'display_order': i},
    ],
    if (p.bidEndTime != null)
      'auctions': [
        {
          'status': 'active',
          'ends_at': p.bidEndTime!.toIso8601String(),
          'current_price': p.currentBid ?? p.startingBid ?? p.price,
          'starting_price': p.startingBid,
          'minimum_increment': p.bidIncrement,
        },
      ],
  };
}

Map<String, dynamic> sellerToHydrateMap(SellerProfile s) {
  return {
    'seller_id': s.sellerId,
    'shop_name': s.shopName,
    'is_approved': s.isVerified,
    'rating_average': s.rating,
    'rating_count': s.ratingCount,
    'total_sales': s.sales,
    'user': {
      'user_id': s.sellerId,
      'username': s.username,
      'full_name': s.ownerName,
      'avatar': s.avatarUrl,
      'rating_average': s.rating,
      'rating_count': s.ratingCount,
      'role': s.isVerified ? 'seller' : 'buyer',
    },
  };
}

List<ProductModel> hydrateCachedProducts(
  List<dynamic> rows,
  Map<String, Map<String, dynamic>> sellers,
) {
  return hydrateCatalogProducts(
    rows,
    sellers,
  ).where((p) => p.status == ProductStatus.active).toList();
}
