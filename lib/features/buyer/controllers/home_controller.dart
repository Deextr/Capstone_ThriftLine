import 'package:flutter/foundation.dart';

import '../../../core/services/supabase_service.dart';
import '../../../models/enums.dart';
import '../../../models/product_model.dart';
import '../../../models/seller_profile.dart';
import '../data/catalog_product_query.dart';

/// Owns the state and data-fetching logic for the Buyer Home / Discover feed.
///
/// The matching screen ([BuyerHomeTab]) reads state via
/// `context.watch<HomeController>()` and delegates actions such as
/// [loadProducts] and [refresh] here.
///
/// Inject this controller at the shell/route level via a
/// [ChangeNotifierProvider].
class HomeController extends ChangeNotifier {
  HomeController({required SupabaseService supabase}) : _supabase = supabase {
    loadProducts();
  }

  final SupabaseService _supabase;

  // â”€â”€ State â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  List<ProductModel> _products = [];
  List<SellerProfile> _verifiedSellers = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<ProductModel> get products => _products;
  List<SellerProfile> get verifiedSellers => _verifiedSellers;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get hasError => _errorMessage != null;

  /// Products currently in auction with an active end-time, sorted soonest
  /// first. Used by the "Ending Soon" carousel.
  List<ProductModel> get endingSoonProducts =>
      _products.where((p) => p.hasActiveBid).toList()..sort(
        (a, b) => (a.bidEndTime ?? DateTime.now()).compareTo(
          b.bidEndTime ?? DateTime.now(),
        ),
      );

  /// The first batch of products for the "Trending Now" grid.
  List<ProductModel> get trendingProducts => _products;

  // â”€â”€ Actions â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Loads active products from Supabase with joined seller, images, and
  /// category data. Called once by the constructor and can be called again
  /// on pull-to-refresh via [refresh].
  Future<void> loadProducts() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await runProductCatalogSelect((select) async {
        return await _supabase.client
            .from('products')
            .select(select)
            .eq('status', 'active')
            .order('created_at', ascending: false)
            .limit(30);
      });

      final rows = response as List<dynamic>;
      final extraIds = rows
          .map((r) => (r as Map<String, dynamic>)['seller_id'] as String?)
          .whereType<String>();
      final sellerProfilesMap = await fetchSellerProfilesMap(
        _supabase.client,
        extraSellerIds: extraIds,
      );

      _products = hydrateCatalogProducts(
        rows,
        sellerProfilesMap,
      ).where((p) => p.status == ProductStatus.active).toList();

      _verifiedSellers = verifiedSellersFromProfiles(sellerProfilesMap);

      final countsBySeller = <String, int>{};
      for (final p in _products) {
        if (p.sellerId != null && p.sellerId!.isNotEmpty) {
          countsBySeller[p.sellerId!] = (countsBySeller[p.sellerId!] ?? 0) + 1;
        }
      }
      _verifiedSellers = _verifiedSellers.map((s) {
        final count = s.sellerId != null
            ? (countsBySeller[s.sellerId!] ?? s.itemCount)
            : s.itemCount;
        return s.copyWith(itemCount: count);
      }).toList();

      _errorMessage = null;
    } catch (e) {
      debugPrint('HomeController.loadProducts error: $e');
      _errorMessage = 'Unable to load products. Please try again.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Pull-to-refresh handler â€” simply re-fetches from Supabase.
  Future<void> refresh() => loadProducts();
}
