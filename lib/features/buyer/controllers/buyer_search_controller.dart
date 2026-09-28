import 'package:flutter/foundation.dart';

import '../../../core/services/shared_preferences_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../models/enums.dart';
import '../../../models/product_model.dart';
import '../data/catalog_product_query.dart';

const _popularSearches = [
  'Vintage Denim',
  'Streetwear',
  'Baggy Jeans',
  'Y2K',
  'Leather Jacket',
  'Sneakers',
];

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
  }) : _supabase = supabase,
       _prefs = prefs,
       _userId = userId {
    final id = _userId;
    if (id != null) {
      _recentSearches = _prefs.recentSearchesFor(id);
    }
  }

  final SupabaseService _supabase;
  final SharedPreferencesService _prefs;
  final String? _userId;

  List<ProductModel> _results = [];
  List<String> _recentSearches = [];
  bool _loading = false;
  String? _errorMessage;

  List<ProductModel> get results => _results;
  List<String> get recentSearches => List.unmodifiable(_recentSearches);
  List<String> get popularSearches => _popularSearches;
  bool get isLoading => _loading;
  String? get errorMessage => _errorMessage;

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
    required String categoryLabel,
    required String sort,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      _results = [];
      _errorMessage = null;
      notifyListeners();
      return;
    }

    if (trimmed.length >= 2) {
      await rememberQuery(trimmed);
    }

    _loading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final sanitized = sanitizeCatalogSearchQuery(trimmed);

      final String orderColumn;
      final bool ascending;
      if (sort == 'Price Low-High') {
        orderColumn = 'price';
        ascending = true;
      } else if (sort == 'Price High-Low') {
        orderColumn = 'price';
        ascending = false;
      } else {
        orderColumn = 'created_at';
        ascending = false;
      }

      final rows = await runProductCatalogSelect((select) async {
        var filterBuilder = _supabase.client
            .from('products')
            .select(select)
            .eq('status', 'active');
        if (sanitized.isNotEmpty) {
          filterBuilder = filterBuilder.or(catalogIlikeOrFilter(sanitized));
        }
        return filterBuilder.order(orderColumn, ascending: ascending).limit(40);
      });

      final extraIds = (rows as List<dynamic>)
          .map((r) => (r as Map<String, dynamic>)['seller_id'] as String?)
          .whereType<String>();
      final sellerProfiles = await fetchSellerProfilesMap(
        _supabase.client,
        extraSellerIds: extraIds,
        includeApproved: false,
      );

      var products = hydrateCatalogProducts(
        rows,
        sellerProfiles,
      ).where((p) => p.status == ProductStatus.active).toList();

      if (categoryLabel != 'All') {
        final needle = categoryLabel.toLowerCase();
        products = products
            .where(
              (p) =>
                  p.category.name.toLowerCase() == needle ||
                  p.category.label.toLowerCase() == needle,
            )
            .toList();
      }

      if (sort == 'Ending Soon') {
        products = products.where((p) => p.hasActiveBid).toList()
          ..sort(
            (a, b) => (a.bidEndTime ?? DateTime.now()).compareTo(
              b.bidEndTime ?? DateTime.now(),
            ),
          );
      }

      _results = products;
    } catch (e) {
      debugPrint('BuyerSearchController.search error: $e');
      _errorMessage = 'Search failed. Please try again.';
      _results = [];
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
