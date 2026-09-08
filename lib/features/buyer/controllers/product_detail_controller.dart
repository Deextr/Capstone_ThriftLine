import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/services/supabase_service.dart';
import '../../../models/enums.dart';
import '../../../models/product_model.dart';
import '../../../providers/auth_provider.dart';
import '../data/catalog_product_query.dart';

/// Controller for the Product Detail screen.
///
/// Fetches the product, its images, seller profile, auction data and bids
/// from Supabase. The matching screen reads state via
/// `context.watch<ProductDetailController>()`.
class ProductDetailController extends ChangeNotifier {
  ProductDetailController({
    required String productId,
    required SupabaseService supabase,
    required AuthProvider auth,
  }) : _productId = productId,
       _supabase = supabase,
       _auth = auth {
    _loadProduct();
  }

  final String _productId;
  final SupabaseService _supabase;
  final AuthProvider _auth;

  // â”€â”€ State â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  ProductModel? _product;
  Map<String, dynamic>? _auction;
  List<Map<String, dynamic>> _bids = [];
  bool _isLoading = true;
  String? _errorMessage;

  ProductModel? get product => _product;
  Map<String, dynamic>? get auction => _auction;
  List<Map<String, dynamic>> get bids => _bids;
  bool get isLoading => _isLoading;
  bool get hasError => _errorMessage != null;
  String? get errorMessage => _errorMessage;

  /// Whether this product is an auction type.
  bool get isAuction =>
      _product != null && _product!.sellingType == SellingType.auction;

  /// The current highest bid amount, falling back to the auction starting
  /// price, then product model current/starting bid, then product fixed price.
  double get currentBidAmount {
    if (_auction != null) {
      final current = (_auction!['current_price'] as num?)?.toDouble();
      if (current != null && current > 0) return current;
      final starting = (_auction!['starting_price'] as num?)?.toDouble();
      if (starting != null && starting > 0) return starting;
    }
    return _product?.currentBid ??
        _product?.startingBid ??
        _product?.price ??
        0;
  }

  /// The minimum increment for the next bid.
  double get minimumIncrement {
    if (_auction == null) return _product?.bidIncrement ?? 20;
    return (_auction!['minimum_increment'] as num?)?.toDouble() ??
        _product?.bidIncrement ??
        20;
  }

  /// Number of bids placed on this auction.
  int get bidCount => _bids.length;

  /// The auction end time (null for fixed-price listings).
  DateTime? get auctionEndTime {
    if (_auction != null) {
      final raw = _auction!['ends_at'] as String?;
      if (raw != null) {
        final parsed = DateTime.tryParse(raw);
        if (parsed != null) return parsed;
      }
    }
    return _product?.bidEndTime;
  }

  /// Whether the auction is still live.
  bool get isAuctionActive {
    if (!isAuction) return false;
    if (_auction != null) {
      final status = _auction!['status'] as String?;
      if (status != null && status != 'active') return false;
    }
    final end = auctionEndTime;
    if (end == null) return false;
    return end.isAfter(DateTime.now());
  }

  // â”€â”€ Actions â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> _loadProduct() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await runProductCatalogSelect((select) async {
        return await _supabase.client
            .from('products')
            .select(select)
            .eq('product_id', _productId)
            .maybeSingle();
      });

      if (response == null) {
        _errorMessage = 'Product not found';
        _isLoading = false;
        notifyListeners();
        return;
      }

      final row = Map<String, dynamic>.from(response as Map);
      Map<String, dynamic>? sellerProfile;
      final sellerId = row['seller_id'] as String?;
      if (sellerId != null) {
        sellerProfile = await fetchHydratedSellerProfile(
          _supabase.client,
          sellerId,
        );
      }

      _product = ProductModel.fromSupabase(row, sellerProfile: sellerProfile);

      unawaited(_incrementView());

      if (_product!.sellingType == SellingType.auction) {
        await _loadAuctionData();
      }

      _errorMessage = null;
    } catch (e) {
      debugPrint('ProductDetailController._loadProduct error: $e');
      _errorMessage = 'Failed to load product details. Please try again.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _incrementView() async {
    try {
      await _supabase.client.rpc(
        'increment_product_view',
        params: {'p_product_id': _productId},
      );
    } catch (e) {
      debugPrint('ProductDetailController.increment_product_view: $e');
    }
  }

  Future<void> _loadAuctionData() async {
    try {
      // Get the auction record for this product
      final auctionResponse = await _supabase.client
          .from('auctions')
          .select()
          .eq('product_id', _productId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      _auction = auctionResponse;

      if (_auction != null) {
        final auctionId = _auction!['auction_id'] as String;

        // Get bids for this auction, ordered newest first
        final bidsResponse = await _supabase.client
            .from('bids')
            .select('''
              *,
              bidder:users!bids_bidder_id_fkey (
                username,
                full_name,
                avatar
              )
            ''')
            .eq('auction_id', auctionId)
            .order('bid_amount', ascending: false);

        _bids = List<Map<String, dynamic>>.from(
          (bidsResponse as List).map((e) => e as Map<String, dynamic>),
        );

        // Update the product model with auction-specific data
        _product = _product!.copyWith(
          currentBid: (_auction!['current_price'] as num?)?.toDouble(),
          startingBid: (_auction!['starting_price'] as num?)?.toDouble(),
          bidIncrement:
              (_auction!['minimum_increment'] as num?)?.toDouble() ?? 20,
          bidEndTime: _auction!['ends_at'] != null
              ? DateTime.tryParse(_auction!['ends_at'] as String)
              : null,
          bidCount: _bids.length,
          bidHistory: _bids
              .map(
                (b) => BidEntry(
                  id: b['bid_id'] as String? ?? '',
                  username:
                      (b['bidder'] as Map<String, dynamic>?)?['username']
                          as String? ??
                      'Anonymous',
                  amount: (b['bid_amount'] as num?)?.toDouble() ?? 0,
                  createdAt: b['created_at'] != null
                      ? DateTime.parse(b['created_at'] as String)
                      : DateTime.now(),
                ),
              )
              .toList(),
        );
      }
    } catch (e) {
      debugPrint('ProductDetailController._loadAuctionData error: $e');
      // Non-fatal â€” auction data is optional
    }
  }

  /// Place a bid on the product's auction.
  /// Returns `null` on success, or an error message string on failure.
  Future<String?> placeBid(double amount) async {
    final userId = _auth.user?.id;
    if (userId == null) {
      return 'Please sign in to place a bid.';
    }

    if (_product?.sellerId != null && _product!.sellerId == userId) {
      return 'Sellers cannot bid on their own listings.';
    }

    final minBid = currentBidAmount + minimumIncrement;
    if (amount < minBid) {
      return 'Bid must be at least ₱${minBid.toStringAsFixed(0)}.';
    }

    // Ensure we have an active auction record
    if (_auction == null) {
      try {
        final existingAuction = await _supabase.client
            .from('auctions')
            .select()
            .eq('product_id', _productId)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();

        if (existingAuction != null) {
          _auction = existingAuction;
        } else if (_product != null &&
            _product!.sellingType == SellingType.auction) {
          // Auto-create active auction row if missing
          final now = DateTime.now().toUtc();
          final endsAt =
              _product!.bidEndTime?.toUtc() ?? now.add(const Duration(days: 3));
          final startingPrice = _product!.startingBid ?? _product!.price;

          final created = await _supabase.client
              .from('auctions')
              .insert({
                'product_id': _productId,
                'starting_price': startingPrice,
                'minimum_increment': _product!.bidIncrement,
                'current_price': startingPrice,
                'starts_at': now.toIso8601String(),
                'ends_at': endsAt.toIso8601String(),
                'status': 'active',
              })
              .select()
              .maybeSingle();

          _auction = created;
        }
      } catch (e) {
        debugPrint('Failed to resolve or create auction row: $e');
      }
    }

    if (_auction == null) {
      return 'Auction record not found for this product.';
    }

    final auctionStatus = _auction!['status'] as String? ?? 'active';
    final rawEndsAt = _auction!['ends_at'] as String?;
    final endsAt = rawEndsAt != null ? DateTime.tryParse(rawEndsAt) : null;
    if (auctionStatus != 'active' ||
        (endsAt != null && endsAt.isBefore(DateTime.now()))) {
      return 'This auction has already ended.';
    }

    final auctionId = _auction!['auction_id'] as String;

    // 1. Try atomic place_bid RPC
    try {
      final rpcRes = await _supabase.client.rpc(
        'place_bid',
        params: {'p_auction_id': auctionId, 'p_amount': amount},
      );

      if (rpcRes is Map) {
        if (rpcRes['success'] == true) {
          await _loadAuctionData();
          notifyListeners();
          return null;
        } else if (rpcRes['error'] != null) {
          return rpcRes['error'].toString();
        }
      }
    } catch (e) {
      debugPrint('place_bid RPC error or missing: $e');
    }

    // 2. Fallback: direct insert into bids table
    try {
      await _supabase.client.from('bids').insert({
        'bidder_id': userId,
        'auction_id': auctionId,
        'bid_amount': amount,
        'is_highest_bid': true,
      });

      // Best effort update
      try {
        await _supabase.client
            .from('bids')
            .update({'is_highest_bid': false})
            .eq('auction_id', auctionId)
            .neq('bidder_id', userId);

        await _supabase.client
            .from('auctions')
            .update({'current_price': amount, 'winner_id': userId})
            .eq('auction_id', auctionId);
      } catch (_) {}

      // Reload auction data to refresh the UI
      await _loadAuctionData();
      notifyListeners();
      return null;
    } catch (e) {
      debugPrint('ProductDetailController.placeBid error: $e');
      return 'Failed to place bid: $e';
    }
  }

  /// Pull-to-refresh â€” re-fetches everything from Supabase.
  Future<void> refresh() => _loadProduct();
}
