import 'package:flutter/foundation.dart';

import '../../../core/services/supabase_service.dart';
import '../../../models/enums.dart';
import '../../../models/product_model.dart';
import '../../../models/seller_profile.dart';

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
      // 1. Fetch seller profiles to build seller_id -> shop info mapping
      final Map<String, Map<String, dynamic>> sellerProfilesMap = {};
      try {
        final spResponse = await _supabase.client
            .from('seller_profiles')
            .select('*, user:user_public_profiles(*)')
            .eq('is_approved', true);

        final spRows = spResponse as List<dynamic>;
        for (final sp in spRows) {
          if (sp is Map<String, dynamic> && sp['seller_id'] != null) {
            sellerProfilesMap[sp['seller_id'] as String] = sp;
          }
        }
      } catch (e) {
        debugPrint('HomeController: seller_profiles fetch error ($e)');
      }

      // Also ensure any verified seller with role == 'seller' in user_public_profiles is included
      try {
        final sellersResponse = await _supabase.client
            .from('user_public_profiles')
            .select()
            .eq('role', 'seller');

        final sellerUsers = sellersResponse as List<dynamic>;
        for (final u in sellerUsers) {
          if (u is Map<String, dynamic>) {
            final uid = u['user_id'] as String?;
            if (uid != null && !sellerProfilesMap.containsKey(uid)) {
              sellerProfilesMap[uid] = {
                'seller_id': uid,
                'shop_name': (u['full_name'] as String?)?.trim().isNotEmpty == true
                    ? u['full_name']
                    : (u['username'] ?? 'Seller'),
                'is_approved': true,
                'user': u,
              };
            }
          }
        }
      } catch (e) {
        debugPrint('HomeController: sellers lookup error ($e)');
      }

      _verifiedSellers = sellerProfilesMap.values
          .map((r) => SellerProfile.fromSupabase(r))
          .where((s) => s.isVerified)
          .toList();

      // 2. Query active products with joined seller public profile, images, category
      final response = await _supabase.client
          .from('products')
          .select('''
            *,
            seller:user_public_profiles (
              user_id,
              username,
              full_name,
              avatar,
              rating_average,
              trust_score,
              role
            ),
            images:product_images (
              image_url,
              is_primary,
              display_order
            ),
            category:categories (
              category_name
            ),
            auctions (
              auction_id,
              starting_price,
              minimum_increment,
              current_price,
              starts_at,
              ends_at,
              status
            )
          ''')
          .eq('status', 'active')
          .order('created_at', ascending: false)
          .limit(30);

      final rows = response as List<dynamic>;

      _products = rows.map((row) {
        final r = row as Map<String, dynamic>;
        final sellerId = r['seller_id'] as String?;
        return ProductModel.fromSupabase(
          r,
          sellerProfile: sellerId != null ? sellerProfilesMap[sellerId] : null,
        );
      }).where((p) => p.status == ProductStatus.active).toList();

      // 3. Fetch active auctions to enrich auction-type products with
      //    bidEndTime, currentBid, etc. for the "Ending Soon" carousel.
      try {
        final auctionResponse = await _supabase.client
            .from('auctions')
            .select()
            .eq('status', 'active');

        final auctionRows = auctionResponse as List<dynamic>;
        final auctionMap = <String, Map<String, dynamic>>{};
        for (final a in auctionRows) {
          final aMap = a as Map<String, dynamic>;
          final productId = aMap['product_id'] as String?;
          if (productId != null) {
            auctionMap[productId] = aMap;
          }
        }

        // Enrich products that have auction data
        _products = _products.map((p) {
          if (p.sellingType != SellingType.auction) return p;
          final auction = auctionMap[p.id];
          if (auction != null) {
            return p.copyWith(
              currentBid: (auction['current_price'] as num?)?.toDouble() ?? p.currentBid,
              startingBid: (auction['starting_price'] as num?)?.toDouble() ?? p.startingBid,
              bidIncrement:
                  (auction['minimum_increment'] as num?)?.toDouble() ?? p.bidIncrement,
              bidEndTime: auction['ends_at'] != null
                  ? DateTime.tryParse(auction['ends_at'] as String)
                  : p.bidEndTime,
            );
          }
          // Ensure valid fallback if no auction row exists in auctions table
          if (p.bidEndTime == null || !p.bidEndTime!.isAfter(DateTime.now())) {
            final fallbackEnd = p.createdAt.add(const Duration(days: 3));
            return p.copyWith(
              startingBid: p.startingBid ?? (p.price > 0 ? p.price : 100),
              currentBid: p.currentBid ?? (p.price > 0 ? p.price : 100),
              bidIncrement: p.bidIncrement > 0 ? p.bidIncrement : 20,
              bidEndTime: fallbackEnd.isAfter(DateTime.now())
                  ? fallbackEnd
                  : DateTime.now().add(const Duration(days: 2)),
            );
          }
          return p;
        }).toList();
      } catch (e) {
        debugPrint('HomeController: auctions fetch error ($e)');
        // Non-fatal — auction enrichment is best-effort
      }

      // 4. Enrich verified sellers with active product count
      final countsBySeller = <String, int>{};
      for (final p in _products) {
        if (p.sellerId != null && p.sellerId!.isNotEmpty) {
          countsBySeller[p.sellerId!] = (countsBySeller[p.sellerId!] ?? 0) + 1;
        }
      }
      _verifiedSellers = _verifiedSellers.map((s) {
        final count = s.sellerId != null ? (countsBySeller[s.sellerId!] ?? s.itemCount) : s.itemCount;
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
