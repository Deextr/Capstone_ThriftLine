import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/services/shared_preferences_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../models/product_model.dart';
import '../data/catalog_product_query.dart';
import '../data/catalog_search_query.dart';
import '../data/search_analytics_service.dart';
import '../models/buyer_search_filters.dart';

/// Newest-first, case-insensitive de-dupe, capped list.
@visibleForTesting
List<String> recordRecentSearch(
  List<String> existing,
  String query, {
  int max = 8,
}) {
  final q = query.trim();
  if (q.isEmpty) return List<String>.from(existing);
  return [
    q,
    ...existing.where((s) => s.toLowerCase() != q.toLowerCase()),
  ].take(max).toList();
}

class BuyerSearchController extends ChangeNotifier {
  BuyerSearchController({
    required SupabaseService supabase,
    required SharedPreferencesService prefs,
    String? userId,
    SearchAnalyticsService? analytics,
  }) : _supabase = supabase,
       _prefs = prefs,
       _userId = userId,
       _analytics = analytics ?? SearchAnalyticsService(supabase.client) {
    final id = _userId;
    if (id != null) {
      _recentSearches = _prefs.recentSearchesFor(id);
    }
    unawaited(bootstrap());
  }

  final SupabaseService _supabase;
  final SharedPreferencesService _prefs;
  final String? _userId;
  final SearchAnalyticsService _analytics;

  List<ProductModel> _results = [];
  List<String> _recentSearches = [];
  List<String> _popularSearches = [];
  List<BuyerCategoryOption> _categories = [];
  BuyerSearchFilters _filters = BuyerSearchFilters.cleared;
  String _lastQuery = '';
  bool _loading = false;
  bool _loadingMore = false;
  bool _loadingMeta = true;
  bool _hasMore = false;
  int _offset = 0;
  String? _errorMessage;

  List<ProductModel> get results => _results;
  List<String> get recentSearches => List.unmodifiable(_recentSearches);
  List<String> get popularSearches => List.unmodifiable(_popularSearches);
  List<BuyerCategoryOption> get categories => List.unmodifiable(_categories);
  BuyerSearchFilters get filters => _filters;
  String get lastQuery => _lastQuery;
  bool get isLoading => _loading;
  bool get isLoadingMore => _loadingMore;
  bool get isLoadingMeta => _loadingMeta;
  bool get hasMore => _hasMore;
  String? get errorMessage => _errorMessage;

  bool get hasBrowseCriteria =>
      _lastQuery.trim().isNotEmpty || _filters.hasActiveFilters;

  Future<void> bootstrap() async {
    _loadingMeta = true;
    notifyListeners();
    try {
      final results = await Future.wait([
        fetchActiveCategories(_supabase.client),
        _analytics.fetchPopularSearches(),
      ]);
      _categories = results[0] as List<BuyerCategoryOption>;
      _popularSearches = results[1] as List<String>;
    } catch (e) {
      debugPrint('BuyerSearchController.bootstrap error: $e');
    } finally {
      _loadingMeta = false;
      notifyListeners();
    }
  }

  void setCategoryId(String? categoryId) {
    _filters = _filters.copyWith(
      categoryId: categoryId,
      clearCategoryId: categoryId == null,
    );
    unawaited(search(query: _lastQuery, reset: true));
  }

  void applyFilters(BuyerSearchFilters filters) {
    _filters = filters;
    unawaited(search(query: _lastQuery, reset: true));
  }

  void resetFilters() {
    _filters = BuyerSearchFilters.cleared;
    unawaited(search(query: _lastQuery, reset: true));
  }

  Future<void> rememberQuery(String query) async {
    _recentSearches = recordRecentSearch(_recentSearches, query);
    notifyListeners();
    final userId = _userId;
    if (userId == null) return;
    await _prefs.setRecentSearches(userId, _recentSearches);
  }

  Future<void> removeRecentSearch(String query) async {
    _recentSearches = _recentSearches.where((s) => s != query).toList();
    notifyListeners();
    final userId = _userId;
    if (userId == null) return;
    await _prefs.setRecentSearches(userId, _recentSearches);
  }

  Future<void> search({
    required String query,
    bool reset = true,
    bool recordAnalytics = false,
  }) async {
    final trimmed = query.trim();
    _lastQuery = trimmed;

    if (trimmed.isEmpty && !_filters.hasActiveFilters) {
      _results = [];
      _errorMessage = null;
      _hasMore = false;
      _offset = 0;
      notifyListeners();
      return;
    }

    if (reset) {
      _offset = 0;
      _hasMore = false;
      _loading = true;
    } else {
      _loadingMore = true;
    }
    _errorMessage = null;
    notifyListeners();

    if (trimmed.length >= 2) {
      await rememberQuery(trimmed);
    }

    try {
      final sanitized = sanitizeCatalogSearchQuery(trimmed);
      final fetchOffset = reset ? 0 : _offset;
      final rows = await fetchCatalogSearchRows(
        _supabase.client,
        sanitizedQuery: sanitized,
        filters: _filters,
        offset: fetchOffset,
      );

      final extraIds = rows
          .map((r) => (r as Map<String, dynamic>)['seller_id'] as String?)
          .whereType<String>();
      final sellerProfiles = await fetchSellerProfilesMap(
        _supabase.client,
        extraSellerIds: extraIds,
        includeApproved: false,
      );

      final products = applySearchResultFilters(
        hydrateCatalogProducts(rows, sellerProfiles),
        _filters,
      );

      if (reset) {
        _results = products;
        _offset = rows.length;
      } else {
        final seen = _results.map((p) => p.id).toSet();
        _results = [
          ..._results,
          ...products.where((p) => !seen.contains(p.id)),
        ];
        _offset += rows.length;
      }

      _hasMore = rows.length >= catalogSearchPageSize;

      if (recordAnalytics && trimmed.length >= 2) {
        unawaited(_analytics.recordSubmittedSearch(trimmed));
      }
    } catch (e) {
      debugPrint('BuyerSearchController.search error: $e');
      _errorMessage = 'Search failed. Please try again.';
      if (reset) _results = [];
    } finally {
      _loading = false;
      _loadingMore = false;
      notifyListeners();
    }
  }

  Future<void> loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;
    await search(query: _lastQuery, reset: false);
  }

  Future<void> submitSearch(String query) async {
    await search(query: query, reset: true, recordAnalytics: true);
  }
}
