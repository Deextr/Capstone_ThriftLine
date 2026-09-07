import 'package:flutter/foundation.dart';

import '../../../core/services/supabase_service.dart';
import '../../../models/enums.dart';
import '../../../models/product_model.dart';

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

  // ── State ──────────────────────────────────────────────────────────────────

  List<ProductModel> _products = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<ProductModel> get products => _products;
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

  // ── Actions ────────────────────────────────────────────────────────────────

  /// Loads active products from Supabase with joined seller, images, and
  /// category data. Called once by the constructor and can be called again
  /// on pull-to-refresh via [refresh].
  Future<void> loadProducts() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // Query active products, newest first, with related data.
      //
      // Join keys:
      //   seller  → users   via products.seller_id = users.user_id
      //   images  → product_images via product_images.product_id
      //   category → categories via products.category_id
      final response = await _supabase.client
          .from('products')
          .select('''
            *,
            seller:users!products_seller_id_fkey (
              user_id,
              username,
              full_name,
              avatar,
              rating_average,
              account_status
            ),
            images:product_images (
              image_url,
              is_primary,
              display_order
            ),
            category:categories (
              category_name
            )
          ''')
          .eq('status', 'active')
          .order('created_at', ascending: false)
          .limit(30);

      final rows = response as List<dynamic>;

      _products = rows
          .map((row) => ProductModel.fromSupabase(row as Map<String, dynamic>))
          .where((p) => p.status == ProductStatus.active)
          .toList();

      _errorMessage = null;
    } catch (e) {
      debugPrint('HomeController.loadProducts error: $e');
      _errorMessage = 'Unable to load products. Please try again.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Pull-to-refresh handler — simply re-fetches from Supabase.
  Future<void> refresh() => loadProducts();
}
