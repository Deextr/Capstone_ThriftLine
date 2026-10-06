import 'package:flutter/foundation.dart';

import '../../../core/services/supabase_service.dart';
import '../../../models/enums.dart';
import '../../../models/product_model.dart';
import '../../../models/seller_profile.dart';
import '../data/catalog_product_query.dart';
import '../data/home_feed_query.dart';
import 'home_controller.dart';

class HomeCollectionController extends ChangeNotifier {
  HomeCollectionController({
    required SupabaseService supabase,
    required this.type,
  }) : _supabase = supabase {
    load();
  }

  static const int _suggestedPageSize = 24;

  final SupabaseService _supabase;
  final HomeCollectionType type;

  List<ProductModel> _products = [];
  List<SellerProfile> _sellers = [];
  Map<String, int> _cartCounts = const {};
  bool _isLoading = false;
  bool _isLoadingMore = false;
  String? _errorMessage;
  String? _loadMoreError;
  bool _isOffline = false;
  bool _hasMoreSuggested = true;
  int _suggestedServerOffset = 0;
  int _loadGeneration = 0;
  bool _disposed = false;

  List<ProductModel> get products => _products;
  List<SellerProfile> get sellers => _sellers;
  Map<String, int> get cartCounts => _cartCounts;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  String? get errorMessage => _errorMessage;
  String? get loadMoreError => _loadMoreError;
  bool get hasError => _errorMessage != null;
  bool get isOffline => _isOffline;
  bool get supportsInfiniteScroll => type == HomeCollectionType.suggested;
  bool get hasMore => _hasMoreSuggested;

  String get title => switch (type) {
    HomeCollectionType.endingSoon => 'Ending Soon',
    HomeCollectionType.suggested => 'Suggested for You',
    HomeCollectionType.bidding => 'Bidding Products',
    HomeCollectionType.verifiedSellers => 'Verified Sellers',
  };

  Future<void> load() async {
    final generation = ++_loadGeneration;
    _isLoading = true;
    _errorMessage = null;
    _loadMoreError = null;
    _isOffline = false;
    if (supportsInfiniteScroll) {
      _hasMoreSuggested = true;
      _suggestedServerOffset = 0;
      _products = [];
      _cartCounts = const {};
    }
    _notify();

    final client = _supabase.client;
    try {
      if (type == HomeCollectionType.verifiedSellers) {
        final map = await fetchSellerProfilesMap(client);
        if (generation != _loadGeneration || _disposed) return;
        _sellers = verifiedSellersFromProfiles(map);
        _products = [];
      } else if (supportsInfiniteScroll) {
        await _appendSuggestedPage(generation: generation, isInitial: true);
      } else {
        List<dynamic> rows;
        List<String>? orderIds;
        if (type == HomeCollectionType.endingSoon) {
          orderIds = await fetchEndingSoonProductIds(client, limit: 40);
          rows = await fetchCatalogProductRows(
            client,
            limit: 40,
            productIds: orderIds,
          );
        } else {
          rows = await fetchCatalogProductRows(
            client,
            limit: 60,
            listingType: 'auction',
          );
        }
        if (generation != _loadGeneration || _disposed) return;

        final extraIds = rows
            .map((r) => (r as Map<String, dynamic>)['seller_id'] as String?)
            .whereType<String>();
        final sellers = await fetchSellerProfilesMap(
          client,
          extraSellerIds: extraIds,
          includeApproved: false,
        );
        if (generation != _loadGeneration || _disposed) return;
        var products = hydrateCatalogProducts(
          rows,
          sellers,
        ).where(isLiveBuyerHomeListing).toList();

        if (type == HomeCollectionType.endingSoon) {
          products = sortProductsByIdOrder(products, orderIds ?? const []);
        }

        _products = products;
        _cartCounts = await fetchProductCartCounts(
          client,
          products
              .where((p) => p.sellingType == SellingType.fixedPrice)
              .map((p) => p.id),
        );
      }
      if (generation == _loadGeneration) {
        _errorMessage = null;
      }
    } catch (e) {
      if (generation != _loadGeneration || _disposed) return;
      debugPrint('HomeCollectionController.load: $e');
      _isOffline = isHomeOfflineError(e);
      _errorMessage = _isOffline
          ? 'You appear to be offline. Connect and try again.'
          : 'Could not load this collection. Please try again.';
    } finally {
      if (generation == _loadGeneration && !_disposed) {
        _isLoading = false;
        _notify();
      }
    }
  }

  Future<void> loadMore() async {
    if (!supportsInfiniteScroll ||
        !_hasMoreSuggested ||
        _isLoading ||
        _isLoadingMore) {
      return;
    }
    final generation = _loadGeneration;
    _isLoadingMore = true;
    _loadMoreError = null;
    _notify();
    try {
      await _appendSuggestedPage(generation: generation, isInitial: false);
    } catch (e) {
      if (generation != _loadGeneration || _disposed) return;
      debugPrint('HomeCollectionController.loadMore: $e');
      _loadMoreError = isHomeOfflineError(e)
          ? 'Could not load more. Check your connection.'
          : 'Could not load more listings. Please try again.';
    } finally {
      if (generation == _loadGeneration && !_disposed) {
        _isLoadingMore = false;
        _notify();
      }
    }
  }

  Future<void> _appendSuggestedPage({
    required int generation,
    required bool isInitial,
  }) async {
    final client = _supabase.client;
    var attempts = 0;
    while (_hasMoreSuggested && attempts < 4) {
      if (generation != _loadGeneration || _disposed) return;
      attempts++;

      List<dynamic> rows;
      try {
        rows = await fetchCatalogProductRows(
          client,
          limit: _suggestedPageSize,
          offset: _suggestedServerOffset,
          orderColumn: 'views',
        );
      } catch (_) {
        rows = await fetchCatalogProductRows(
          client,
          limit: _suggestedPageSize,
          offset: _suggestedServerOffset,
          orderColumn: 'created_at',
        );
      }
      if (generation != _loadGeneration || _disposed) return;

      _suggestedServerOffset += rows.length;
      if (rows.length < _suggestedPageSize) {
        _hasMoreSuggested = false;
      }
      if (rows.isEmpty) {
        _hasMoreSuggested = false;
        break;
      }

      final extraIds = rows
          .map((r) => (r as Map<String, dynamic>)['seller_id'] as String?)
          .whereType<String>();
      final sellers = await fetchSellerProfilesMap(
        client,
        extraSellerIds: extraIds,
        includeApproved: false,
      );
      if (generation != _loadGeneration || _disposed) return;

      final batch = hydrateCatalogProducts(
        rows,
        sellers,
      ).where(isLiveBuyerHomeListing).toList();

      final existingIds = _products.map((p) => p.id).toSet();
      final appended = <ProductModel>[];
      for (final product in batch) {
        if (existingIds.add(product.id)) {
          appended.add(product);
        }
      }
      _products = [..._products, ...appended];

      if (appended.isNotEmpty || !_hasMoreSuggested) break;
      // Server page had only filtered-out listings; fetch next offset.
    }

    if (generation != _loadGeneration || _disposed) return;
    if (_products.isEmpty && isInitial) return;

    final newFixed = _products
        .where((p) => p.sellingType == SellingType.fixedPrice)
        .map((p) => p.id)
        .where((id) => !_cartCounts.containsKey(id));
    if (newFixed.isNotEmpty) {
      final counts = await fetchProductCartCounts(client, newFixed);
      if (generation != _loadGeneration || _disposed) return;
      _cartCounts = {..._cartCounts, ...counts};
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _loadGeneration++;
    super.dispose();
  }
}
