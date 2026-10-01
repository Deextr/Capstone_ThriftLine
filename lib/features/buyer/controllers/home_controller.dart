import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/services/shared_preferences_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../models/enums.dart';
import '../../../models/product_model.dart';
import '../../../models/seller_profile.dart';
import '../data/catalog_product_query.dart';
import '../data/home_feed_query.dart';

/// Owns Buyer Home feed sections, batched cart popularity, and offline cache.
class HomeController extends ChangeNotifier {
  HomeController({
    required SupabaseService supabase,
    SharedPreferencesService? prefs,
  }) : _supabase = supabase,
       _prefs = prefs {
    loadProducts();
  }

  final SupabaseService _supabase;
  final SharedPreferencesService? _prefs;

  HomeFeedSection<ProductModel> _endingSoon = const HomeFeedSection(
    isLoading: true,
  );
  HomeFeedSection<ProductModel> _suggested = const HomeFeedSection(
    isLoading: true,
  );
  HomeFeedSection<ProductModel> _bidding = const HomeFeedSection(
    isLoading: true,
  );
  HomeFeedSection<SellerProfile> _verifiedSellers = const HomeFeedSection(
    isLoading: true,
  );

  Map<String, int> _cartCounts = const {};
  bool _isLoading = false;
  bool _isOffline = false;
  bool _showingCachedData = false;
  String? _errorMessage;

  HomeFeedSection<ProductModel> get endingSoon => _endingSoon;
  HomeFeedSection<ProductModel> get suggested => _suggested;
  HomeFeedSection<ProductModel> get bidding => _bidding;
  HomeFeedSection<SellerProfile> get verifiedSellersSection => _verifiedSellers;

  List<ProductModel> get endingSoonProducts => _endingSoon.items;
  List<ProductModel> get suggestedProducts => _suggested.items;
  List<ProductModel> get biddingProducts => _bidding.items;
  List<SellerProfile> get verifiedSellers => _verifiedSellers.items;

  /// Combined active listings for callers that still read a single list.
  List<ProductModel> get products {
    final seen = <String>{};
    final all = <ProductModel>[];
    for (final p in [
      ..._endingSoon.items,
      ..._suggested.items,
      ..._bidding.items,
    ]) {
      if (seen.add(p.id)) all.add(p);
    }
    return all;
  }

  List<ProductModel> get trendingProducts => _suggested.items;

  Map<String, int> get cartCounts => _cartCounts;
  int cartCountFor(String productId) => _cartCounts[productId] ?? 0;

  bool get isLoading => _isLoading;
  bool get isOffline => _isOffline;
  bool get showingCachedData => _showingCachedData;
  String? get errorMessage => _errorMessage;
  bool get hasError => _errorMessage != null && products.isEmpty;

  bool get hasAnyContent =>
      _endingSoon.items.isNotEmpty ||
      _suggested.items.isNotEmpty ||
      _bidding.items.isNotEmpty ||
      _verifiedSellers.items.isNotEmpty;

  Future<void> loadProducts() async {
    _isLoading = true;
    _errorMessage = null;
    _isOffline = false;
    _endingSoon = _endingSoon.copyWith(isLoading: true, clearError: true);
    _suggested = _suggested.copyWith(isLoading: true, clearError: true);
    _bidding = _bidding.copyWith(isLoading: true, clearError: true);
    _verifiedSellers = _verifiedSellers.copyWith(
      isLoading: true,
      clearError: true,
    );
    notifyListeners();

    final client = _supabase.client;

    List<ProductModel> ending = const [];
    List<ProductModel> suggested = const [];
    List<ProductModel> bidding = const [];
    List<SellerProfile> sellers = const [];
    String? endingError;
    String? suggestedError;
    String? biddingError;
    String? sellersError;
    var anyOffline = false;

    Future<void> loadEndingSoon() async {
      try {
        final ids = await fetchEndingSoonProductIds(client, limit: 16);
        if (ids.isEmpty) {
          ending = const [];
          return;
        }
        final rows = await fetchCatalogProductRows(
          client,
          limit: ids.length,
          productIds: ids,
        );
        ending = sortProductsByIdOrder(
          hydrateCatalogProducts(rows, const {}).where(_isActive).toList(),
          ids,
        ).where(isLiveBuyerHomeListing).toList();
      } catch (e) {
        debugPrint('HomeController ending soon: $e');
        anyOffline = anyOffline || isHomeOfflineError(e);
        endingError = 'Could not load auctions ending soon.';
      }
    }

    Future<void> loadSuggested() async {
      try {
        List<dynamic> rows;
        try {
          rows = await fetchCatalogProductRows(
            client,
            limit: 16,
            orderColumn: 'views',
          );
        } catch (_) {
          rows = await fetchCatalogProductRows(
            client,
            limit: 16,
            orderColumn: 'created_at',
          );
        }
        suggested = hydrateCatalogProducts(
          rows,
          const {},
        ).where(isLiveBuyerHomeListing).toList();
      } catch (e) {
        debugPrint('HomeController suggested: $e');
        anyOffline = anyOffline || isHomeOfflineError(e);
        suggestedError = 'Could not load suggested listings.';
      }
    }

    Future<void> loadBidding() async {
      try {
        final rows = await fetchCatalogProductRows(
          client,
          limit: 30,
          listingType: 'auction',
        );
        bidding = hydrateCatalogProducts(
          rows,
          const {},
        ).where(isLiveBuyerHomeListing).take(16).toList();
      } catch (e) {
        debugPrint('HomeController bidding: $e');
        anyOffline = anyOffline || isHomeOfflineError(e);
        biddingError = 'Could not load bidding products.';
      }
    }

    Future<void> loadSellers() async {
      try {
        final map = await fetchSellerProfilesMap(client);
        sellers = verifiedSellersFromProfiles(map);
      } catch (e) {
        debugPrint('HomeController sellers: $e');
        anyOffline = anyOffline || isHomeOfflineError(e);
        sellersError = 'Could not load verified sellers.';
      }
    }

    await Future.wait([
      loadEndingSoon(),
      loadSuggested(),
      loadBidding(),
      loadSellers(),
    ]);

    final extraIds = <String>{
      for (final p in [...ending, ...suggested, ...bidding])
        if (p.sellerId != null && p.sellerId!.isNotEmpty) p.sellerId!,
    };

    Map<String, Map<String, dynamic>> sellerProfiles = const {};
    try {
      sellerProfiles = await fetchSellerProfilesMap(
        client,
        extraSellerIds: extraIds,
      );
    } catch (e) {
      debugPrint('HomeController seller hydrate: $e');
    }

    if (sellerProfiles.isNotEmpty) {
      ending = _rehydrate(ending, sellerProfiles);
      suggested = _rehydrate(suggested, sellerProfiles);
      bidding = _rehydrate(bidding, sellerProfiles);
      if (sellers.isEmpty) {
        sellers = verifiedSellersFromProfiles(sellerProfiles);
      }
    }

    final countsBySeller = <String, int>{};
    for (final p in [...ending, ...suggested, ...bidding]) {
      final id = p.sellerId;
      if (id != null && id.isNotEmpty) {
        countsBySeller[id] = (countsBySeller[id] ?? 0) + 1;
      }
    }
    sellers = sellers.map((s) {
      final count = s.sellerId != null
          ? (countsBySeller[s.sellerId!] ?? s.itemCount)
          : s.itemCount;
      return s.copyWith(itemCount: count);
    }).toList();

    final cartProductIds = [
      ...ending,
      ...suggested,
      ...bidding,
    ].where((p) => p.sellingType == SellingType.fixedPrice).map((p) => p.id);

    var cartCounts = <String, int>{};
    try {
      cartCounts = await fetchProductCartCounts(client, cartProductIds);
    } catch (e) {
      debugPrint('HomeController cart counts: $e');
    }

    final failedEverything =
        endingError != null &&
        suggestedError != null &&
        biddingError != null &&
        sellersError != null;

    if (failedEverything) {
      final restored = _restoreCache();
      _isLoading = false;
      _isOffline = anyOffline;
      if (restored) {
        _showingCachedData = true;
        _errorMessage = null;
      } else {
        _errorMessage = anyOffline
            ? 'You appear to be offline. Connect to the internet and try again.'
            : 'Unable to load products. Please try again.';
        _endingSoon = HomeFeedSection(errorMessage: endingError);
        _suggested = HomeFeedSection(errorMessage: suggestedError);
        _bidding = HomeFeedSection(errorMessage: biddingError);
        _verifiedSellers = HomeFeedSection(errorMessage: sellersError);
      }
      notifyListeners();
      return;
    }

    _endingSoon = HomeFeedSection(items: ending, errorMessage: endingError);
    _suggested = HomeFeedSection(
      items: suggested,
      errorMessage: suggestedError,
    );
    _bidding = HomeFeedSection(items: bidding, errorMessage: biddingError);
    _verifiedSellers = HomeFeedSection(
      items: sellers,
      errorMessage: sellersError,
    );
    _cartCounts = cartCounts;
    _isOffline = anyOffline;
    _showingCachedData = false;
    _errorMessage = null;
    _isLoading = false;
    _saveCache();
    notifyListeners();
  }

  Future<void> refresh() => loadProducts();

  bool _isActive(ProductModel p) => p.status == ProductStatus.active;

  List<ProductModel> _rehydrate(
    List<ProductModel> products,
    Map<String, Map<String, dynamic>> sellers,
  ) {
    if (products.isEmpty) return products;
    return products.map((p) {
      final row = productToCacheRow(p);
      return ProductModel.fromSupabase(
        row,
        sellerProfile: p.sellerId != null ? sellers[p.sellerId!] : null,
      );
    }).toList();
  }

  void _saveCache() {
    final prefs = _prefs;
    if (prefs == null) return;
    try {
      final payload = {
        'endingSoon': endingSoonProducts.map(productToCacheRow).toList(),
        'suggested': suggestedProducts.map(productToCacheRow).toList(),
        'bidding': biddingProducts.map(productToCacheRow).toList(),
        'sellers': verifiedSellers.map(sellerToHydrateMap).toList(),
        'cartCounts': _cartCounts,
      };
      prefs.setBuyerHomeCacheJson(jsonEncode(payload));
    } catch (e) {
      debugPrint('HomeController cache save: $e');
    }
  }

  bool _restoreCache() {
    final raw = _prefs?.buyerHomeCacheJson;
    if (raw == null || raw.isEmpty) return false;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return false;
      final sellersList = (decoded['sellers'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final sellerMap = <String, Map<String, dynamic>>{};
      for (final row in sellersList) {
        final id = row['seller_id'] as String?;
        if (id != null) sellerMap[id] = row;
      }

      List<ProductModel> readProducts(String key) {
        final rows = decoded[key] as List<dynamic>? ?? [];
        return hydrateCachedProducts(
          rows,
          sellerMap,
        ).where(isLiveBuyerHomeListing).toList();
      }

      _endingSoon = HomeFeedSection(items: readProducts('endingSoon'));
      _suggested = HomeFeedSection(items: readProducts('suggested'));
      _bidding = HomeFeedSection(items: readProducts('bidding'));
      _verifiedSellers = HomeFeedSection(
        items: sellersList.map(SellerProfile.fromSupabase).toList(),
      );
      final counts = decoded['cartCounts'];
      if (counts is Map) {
        _cartCounts = {
          for (final e in counts.entries)
            e.key.toString(): (e.value as num?)?.toInt() ?? 0,
        };
      }
      return hasAnyContent;
    } catch (e) {
      debugPrint('HomeController cache restore: $e');
      return false;
    }
  }
}

enum HomeCollectionType { endingSoon, suggested, bidding, verifiedSellers }
