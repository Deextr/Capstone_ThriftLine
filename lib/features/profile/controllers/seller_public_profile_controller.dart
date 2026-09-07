import 'package:flutter/foundation.dart';

import '../../../core/services/supabase_service.dart';
import '../../../models/enums.dart';
import '../../../models/product_model.dart';
import '../../../models/review_model.dart';
import '../../../models/seller_profile.dart';
import '../../../providers/auth_provider.dart';

/// Owns the state and database query logic for a public seller profile.
///
/// Fetches the seller's public profile, listing products, and customer reviews
/// directly from Supabase.
class SellerPublicProfileController extends ChangeNotifier {
  SellerPublicProfileController({
    required String username,
    required SupabaseService supabase,
    AuthProvider? auth,
  })  : _username = username,
        _supabase = supabase,
        _auth = auth {
    loadSellerProfile();
  }

  final String _username;
  final SupabaseService _supabase;
  final AuthProvider? _auth;

  // â”€â”€ State â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  SellerProfile? _sellerProfile;
  List<ProductModel> _products = [];
  List<ReviewModel> _reviews = [];
  bool _isLoading = true;
  bool _isFollowing = false;
  String? _errorMessage;

  SellerProfile? get sellerProfile => _sellerProfile;
  List<ProductModel> get products => _products;
  List<ReviewModel> get reviews => _reviews;
  bool get isLoading => _isLoading;
  bool get isFollowing => _isFollowing;
  String? get errorMessage => _errorMessage;
  bool get hasError => _errorMessage != null;
  String get username => _username;
  bool get isCurrentUser =>
      _auth?.user?.id != null &&
      (_sellerProfile?.sellerId == _auth?.user?.id ||
          _auth?.user?.username == _username);

  int get soldCount {
    if (_sellerProfile != null && _sellerProfile!.sales > 0) {
      return _sellerProfile!.sales;
    }
    return _products.where((p) => p.status == ProductStatus.sold).length;
  }

  int get activeListingsCount =>
      _products.where((p) => p.status == ProductStatus.active).length;

  double get averageRating {
    if (_reviews.isNotEmpty) {
      final total = _reviews.fold<double>(0, (sum, r) => sum + r.rating);
      return total / _reviews.length;
    }
    return _sellerProfile?.rating ?? 5.0;
  }

  int get totalReviewCount =>
      _reviews.isNotEmpty ? _reviews.length : (_sellerProfile?.ratingCount ?? 0);

  // â”€â”€ Database Actions â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Fetches seller profile, products, and reviews from Supabase.
  Future<void> loadSellerProfile() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // 1. Fetch user public profile by username
      Map<String, dynamic>? userRow;
      try {
        final userQuery = await _supabase.client
            .from('user_public_profiles')
            .select()
            .eq('username', _username)
            .maybeSingle();

        userRow = userQuery;
      } catch (e) {
        debugPrint('user_public_profiles lookup by username error: $e');
      }

      // Fallback: search by user_id if username was a UUID
      if (userRow == null) {
        try {
          final uuidRegex = RegExp(
              r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
          if (uuidRegex.hasMatch(_username)) {
            userRow = await _supabase.client
                .from('user_public_profiles')
                .select()
                .eq('user_id', _username)
                .maybeSingle();
          }
        } catch (_) {}
      }

      // Fallback: search direct users table if view was unavailable
      if (userRow == null) {
        try {
          userRow = await _supabase.client
              .from('users')
              .select('user_id, username, full_name, avatar, role, trust_score, rating_average, rating_count, bio, location, created_at')
              .eq('username', _username)
              .maybeSingle();
        } catch (e) {
          debugPrint('users lookup by username error: $e');
        }
      }

      if (userRow == null) {
        _errorMessage = 'Seller not found';
        _isLoading = false;
        notifyListeners();
        return;
      }

      final sellerUserId = userRow['user_id'] as String;

      // 2. Fetch seller_profiles entry for shop name, bio, total_sales, follower_count
      Map<String, dynamic>? sellerProfileRow;
      try {
        sellerProfileRow = await _supabase.client
            .from('seller_profiles')
            .select()
            .eq('seller_id', sellerUserId)
            .maybeSingle();
      } catch (e) {
        debugPrint('seller_profiles lookup error: $e');
      }

      // 3. Query all products listed by this seller
      try {
        final productsResponse = await _supabase.client
            .from('products')
            .select('''
              *,
              images:product_images (
                image_url,
                is_primary,
                display_order
              ),
              category:categories (
                category_name
              )
            ''')
            .eq('seller_id', sellerUserId)
            .order('created_at', ascending: false);

        final rawProducts = productsResponse as List<dynamic>;

        _products = rawProducts.map((p) {
          final r = p as Map<String, dynamic>;
          return ProductModel.fromSupabase(
            r,
            sellerProfile: sellerProfileRow,
          );
        }).toList();

        // 4. Enrich auction products with auction status/bids if any
        final auctionProducts =
            _products.where((p) => p.sellingType == SellingType.auction).toList();

        if (auctionProducts.isNotEmpty) {
          try {
            final auctionResponse = await _supabase.client
                .from('auctions')
                .select()
                .inFilter('product_id', auctionProducts.map((p) => p.id).toList());

            final auctionRows = auctionResponse as List<dynamic>;
            final auctionMap = <String, Map<String, dynamic>>{};
            for (final a in auctionRows) {
              final aMap = a as Map<String, dynamic>;
              final pid = aMap['product_id'] as String?;
              if (pid != null) {
                auctionMap[pid] = aMap;
              }
            }

            _products = _products.map((p) {
              final auction = auctionMap[p.id];
              if (auction == null) return p;
              return p.copyWith(
                currentBid: (auction['current_price'] as num?)?.toDouble(),
                startingBid: (auction['starting_price'] as num?)?.toDouble(),
                bidIncrement:
                    (auction['minimum_increment'] as num?)?.toDouble() ?? 20,
                bidEndTime: auction['ends_at'] != null
                    ? DateTime.tryParse(auction['ends_at'] as String)
                    : null,
              );
            }).toList();
          } catch (e) {
            debugPrint('seller auction enrichment error: $e');
          }
        }
      } catch (e) {
        debugPrint('products fetch for seller error: $e');
        _products = [];
      }

      // 5. Query reviews for this seller
      try {
        final reviewsResponse = await _supabase.client
            .from('reviews')
            .select('''
              *,
              reviewer:user_public_profiles (
                user_id,
                username,
                full_name,
                avatar
              )
            ''')
            .eq('reviewed_user_id', sellerUserId)
            .order('created_at', ascending: false);

        final rawReviews = reviewsResponse as List<dynamic>;
        _reviews = rawReviews
            .map((r) => ReviewModel.fromSupabase(r as Map<String, dynamic>))
            .toList();
      } catch (e) {
        debugPrint('reviews fetch for seller error: $e');
        _reviews = [];
      }

      // 6. Build the unified SellerProfile
      _sellerProfile = SellerProfile.fromSupabase(
        sellerProfileRow ?? {},
        userRow: userRow,
        activeProductCount: activeListingsCount,
        totalProductCount: _products.length,
      );

      _errorMessage = null;
    } catch (e) {
      debugPrint('SellerPublicProfileController.loadSellerProfile error: $e');
      _errorMessage = 'Unable to load seller information. Please try again.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Toggles the follow status for this seller.
  void toggleFollow() {
    _isFollowing = !_isFollowing;
    if (_sellerProfile != null) {
      final currentFollowers = _sellerProfile!.followerCount;
      final newFollowers = _isFollowing
          ? currentFollowers + 1
          : (currentFollowers > 0 ? currentFollowers - 1 : 0);

      _sellerProfile = _sellerProfile!.copyWith(followerCount: newFollowers);
    }
    notifyListeners();
  }

  /// Pull-to-refresh handler.
  Future<void> refresh() => loadSellerProfile();
}
