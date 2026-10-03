import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/utils/supabase_rpc.dart';
import '../../../models/enums.dart';
import '../../../models/product_model.dart';
import '../../../providers/auth_provider.dart';
import '../../chat/data/conversation_service.dart';
import '../../seller/data/listing_bucket.dart';
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
    ConversationService? conversations,
    this.ownerPreviewMode = false,
  }) : _productId = productId,
       _supabase = supabase,
       _auth = auth,
       _conversations = conversations ?? ConversationService(supabase) {
    _loadProduct();
  }

  final String _productId;
  final SupabaseService _supabase;
  final AuthProvider _auth;
  final ConversationService _conversations;

  /// Read-only seller preview from My Listings (no purchase/bid actions).
  final bool ownerPreviewMode;

  ProductModel? _product;
  Map<String, dynamic>? _auction;
  List<Map<String, dynamic>> _bids = [];
  Map<String, dynamic>? _auctionOrder;
  bool _isLoading = true;
  String? _errorMessage;
  RealtimeChannel? _auctionChannel;
  Timer? _reloadDebounce;
  String? _subscribedAuctionId;
  bool _disposed = false;

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

  /// Minimum amount the next bid must meet.
  double get minimumNextBid => currentBidAmount + minimumIncrement;

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

  bool get isOwnListing {
    final uid = _auth.user?.id;
    final sellerId = _product?.sellerId;
    return uid != null && sellerId != null && uid == sellerId;
  }

  ListingSnapshot? get _listingSnapshot {
    final product = _product;
    if (product == null) return null;
    final listingType = product.sellingType == SellingType.auction
        ? 'auction'
        : 'fixed_price';
    return ListingSnapshot(
      productStatus: product.status.name,
      listingType: listingType,
      auctionStatus: _auction?['status'] as String?,
      endsAt: auctionEndTime,
      winnerId: _auction?['winner_id'] as String?,
      orderStatus: _auctionOrder?['order_status'] as String?,
      paymentDueAt: paymentDueAt,
      bidCount: bidCount,
      now: DateTime.now(),
    );
  }

  /// Matches My Listings: edit is only offered for listings in the Active bucket.
  bool get canSellerEditListing {
    if (!isOwnListing) return false;
    final snapshot = _listingSnapshot;
    if (snapshot == null) return false;
    return canEditListing(snapshot);
  }

  String get ownerListingStatusLabel {
    final snapshot = _listingSnapshot;
    if (snapshot == null) return '';
    return switch (listingBucketFor(snapshot)) {
      ListingBucket.active => 'Active',
      ListingBucket.awaitingPayment => 'Awaiting payment',
      ListingBucket.sold => 'Sold',
      ListingBucket.inactive => 'Inactive',
    };
  }

  String? get auctionId => _auction?['auction_id'] as String?;

  /// The payment deadline for the viewer's won-auction order.
  DateTime? get paymentDueAt {
    final raw = _auctionOrder?['payment_due_at'] as String?;
    return raw != null ? DateTime.tryParse(raw) : null;
  }

  /// Whether the viewer's payment window has expired.
  bool get isPaymentExpired {
    final due = paymentDueAt;
    if (due == null) return false;
    return due.isBefore(DateTime.now());
  }

  /// Order status for the viewer's auction order (e.g. 'pending', 'cancelled').
  String? get auctionOrderStatus => _auctionOrder?['order_status'] as String?;

  /// Current bid round (incremented on each relist).
  int get bidRound => (_auction?['bid_round'] as num?)?.toInt() ?? 1;

  /// Auction starting price (used to pre-fill the relist form).
  double get auctionStartingPrice =>
      (_auction?['starting_price'] as num?)?.toDouble() ?? _product?.price ?? 0;

  /// Auction minimum increment (used to pre-fill the relist form).
  double get auctionMinimumIncrement =>
      (_auction?['minimum_increment'] as num?)?.toDouble() ?? 20;

  /// Auction duration in days (used to pre-fill the relist form).
  int get auctionDurationDays =>
      (_auction?['duration_days'] as num?)?.toInt() ?? 3;

  /// Seller may close only while bidding is still open and someone has bid.
  bool get canEndAuctionEarly =>
      isOwnListing && isAuctionActive && bidCount > 0;

  Future<String?> endAuctionEarly() async {
    final id = auctionId;
    if (id == null || id.isEmpty) return 'Auction not found.';
    if (!canEndAuctionEarly) {
      return 'End the auction early only after someone has bid.';
    }
    try {
      final result = await _supabase.client.rpc(
        'end_auction_early',
        params: {'p_auction_id': id},
      );
      if (!supabaseRpcSuccess(result)) {
        return supabaseRpcError(
          result,
          fallback: 'Could not end this auction.',
        );
      }
      await _loadAuctionData();
      notifyListeners();
      return null;
    } catch (e) {
      debugPrint('ProductDetailController.endAuctionEarly: $e');
      return 'Could not end this auction.';
    }
  }

  bool get isViewerLeading {
    final uid = _auth.user?.id;
    if (uid == null || !isAuction) return false;
    final winnerId = _auction?['winner_id'] as String?;
    if (winnerId == uid) return true;
    if (_bids.isEmpty) return false;
    return _bids.first['bidder_id'] == uid;
  }

  bool get isViewerWinner {
    final uid = _auth.user?.id;
    if (uid == null || !isAuction || isAuctionActive) return false;
    if (_auction?['winner_id'] != uid) return false;
    // If the order was cancelled (payment expired), the viewer is no longer
    // considered a winner who can proceed to checkout.
    if (auctionOrderStatus == 'cancelled') return false;
    return true;
  }

  /// Whether the viewer won the auction but their payment window expired.
  bool get isViewerExpiredWinner {
    final uid = _auth.user?.id;
    if (uid == null || !isAuction || isAuctionActive) return false;
    return _auction?['winner_id'] == uid && auctionOrderStatus == 'cancelled';
  }

  bool get hasNoWinner {
    if (!isAuction || isAuctionActive) return false;
    final winnerId = _auction?['winner_id'] as String?;
    return winnerId == null || winnerId.isEmpty || _bids.isEmpty;
  }

  bool get canOfferToNextBidder {
    if (!isOwnListing || !isAuction || isAuctionActive) return false;
    if (_product?.status == ProductStatus.sold) return false;
    return _bids.length >= 2;
  }

  bool isViewerBid(Map<String, dynamic> bid) {
    final uid = _auth.user?.id;
    return uid != null && bid['bidder_id'] == uid;
  }

  String? get viewerAuctionStatus {
    if (!isAuction) return null;
    final uid = _auth.user?.id;
    if (uid == null) return null;
    final hasBid = _bids.any((b) => b['bidder_id'] == uid);
    if (!isAuctionActive) {
      if (isViewerExpiredWinner) {
        return 'Payment window expired — Item no longer available';
      }
      if (isViewerWinner) {
        final due = paymentDueAt;
        if (due != null) {
          final diff = due.difference(DateTime.now());
          if (!diff.isNegative) {
            final hours = diff.inHours;
            final mins = diff.inMinutes % 60;
            return 'You won! Pay within ${hours}h ${mins}m';
          }
        }
        return 'You won this auction';
      }
      if (hasNoWinner) return 'Auction ended — No winner';
      if (hasBid) return 'You did not win this auction';
      return 'Auction ended';
    }
    if (!hasBid) return null;
    if (isViewerLeading) return "You're leading (Highest bidder)";
    return "You've been outbid";
  }

  Future<String?> getWonAuctionOrderId() async {
    final aid = auctionId;
    final uid = _auth.user?.id;
    if (aid == null || uid == null) return null;
    try {
      final row = await _supabase.client
          .from('orders')
          .select('order_id')
          .eq('auction_id', aid)
          .eq('buyer_id', uid)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (row != null && row['order_id'] != null) {
        return row['order_id'] as String;
      }
      final rpcRes = await _supabase.client.rpc(
        'ensure_auction_order',
        params: {'p_auction_id': aid},
      );
      if (rpcRes != null) return rpcRes.toString();
    } catch (e) {
      debugPrint('ProductDetailController.getWonAuctionOrderId error: $e');
    }
    return null;
  }

  Future<String?> offerToNextBidder() async {
    final aid = auctionId;
    if (aid == null) return 'Auction not found.';
    try {
      final result = await _supabase.client.rpc(
        'offer_auction_to_next_bidder',
        params: {'p_auction_id': aid},
      );
      if (!supabaseRpcSuccess(result)) {
        return supabaseRpcError(
          result,
          fallback: 'Could not send offer to next bidder.',
        );
      }
      await _loadAuctionData();
      notifyListeners();
      return null;
    } catch (e) {
      debugPrint('ProductDetailController.offerToNextBidder error: $e');
      return 'Could not send offer to next bidder.';
    }
  }

  Future<String?> relistAuction(
    int days, {
    double? startingPrice,
    double? minimumIncrement,
  }) async {
    if (_productId.isEmpty) return 'Product not found.';
    try {
      final params = <String, dynamic>{
        'p_product_id': _productId,
        'p_duration_days': days,
      };
      if (startingPrice != null) params['p_starting_price'] = startingPrice;
      if (minimumIncrement != null) {
        params['p_minimum_increment'] = minimumIncrement;
      }
      final result = await _supabase.client.rpc(
        'relist_unsold_auction',
        params: params,
      );
      if (!supabaseRpcSuccess(result)) {
        return supabaseRpcError(
          result,
          fallback: 'Could not relist this auction.',
        );
      }
      await _loadProduct();
      return null;
    } catch (e) {
      debugPrint('ProductDetailController.relistAuction error: $e');
      return 'Could not relist this auction.';
    }
  }

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

      if (!isOwnListing) {
        unawaited(_incrementView());
      }

      if (_product!.sellingType == SellingType.auction) {
        await _closeExpiredAuctions();
        await _loadAuctionData();
        _subscribeAuctionRealtime();
      } else {
        await _unsubscribeAuctionRealtime();
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

  Future<void> _closeExpiredAuctions() async {
    try {
      await _supabase.client.rpc('close_auctions');
    } catch (e) {
      debugPrint('ProductDetailController.close_auctions: $e');
    }
  }

  Future<void> _loadAuctionData() async {
    try {
      final auctionResponse = await _supabase.client
          .from('auctions')
          .select()
          .eq('product_id', _productId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      _auction = auctionResponse;

      if (_auction != null && _product != null) {
        final auctionId = _auction!['auction_id'] as String;

        final currentRound = (_auction!['bid_round'] as num?)?.toInt() ?? 1;

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
            .eq('bid_round', currentRound)
            .order('bid_amount', ascending: false);

        _bids = List<Map<String, dynamic>>.from(
          (bidsResponse as List).map((e) => e as Map<String, dynamic>),
        );

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

        // Load the current viewer's auction order to check payment status
        final uid = _auth.user?.id;
        if (uid != null) {
          try {
            _auctionOrder = await _supabase.client
                .from('orders')
                .select('order_id, order_status, payment_due_at')
                .eq('auction_id', auctionId)
                .eq('buyer_id', uid)
                .order('created_at', ascending: false)
                .limit(1)
                .maybeSingle();
          } catch (e) {
            debugPrint('_loadAuctionData order query: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('ProductDetailController._loadAuctionData error: $e');
    }
  }

  void _subscribeAuctionRealtime() {
    final auctionId = _auction?['auction_id'] as String?;
    if (auctionId == null || auctionId.isEmpty) return;
    if (_subscribedAuctionId == auctionId && _auctionChannel != null) return;

    unawaited(_unsubscribeAuctionRealtime());
    _subscribedAuctionId = auctionId;

    try {
      _auctionChannel = _supabase.client
          .channel('auction-detail-$auctionId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'auctions',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'auction_id',
              value: auctionId,
            ),
            callback: (_) => _scheduleAuctionReload(),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'bids',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'auction_id',
              value: auctionId,
            ),
            callback: (_) => _scheduleAuctionReload(),
          )
          .subscribe();
    } catch (e) {
      debugPrint('ProductDetailController realtime error: $e');
    }
  }

  void _scheduleAuctionReload() {
    _reloadDebounce?.cancel();
    _reloadDebounce = Timer(const Duration(milliseconds: 250), () async {
      if (_disposed) return;
      await _loadAuctionData();
      if (!_disposed) notifyListeners();
    });
  }

  Future<void> _unsubscribeAuctionRealtime() async {
    final channel = _auctionChannel;
    _auctionChannel = null;
    _subscribedAuctionId = null;
    if (channel != null) {
      try {
        await _supabase.client.removeChannel(channel);
      } catch (e) {
        debugPrint('ProductDetailController unsubscribe error: $e');
      }
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

    if (isViewerLeading) {
      return 'You are already the highest bidder.';
    }

    final minBid = minimumNextBid;
    if (amount < minBid) {
      return 'Bid must be at least ₱${minBid.toStringAsFixed(0)}.';
    }

    if (_auction == null) {
      try {
        final existingAuction = await _supabase.client
            .from('auctions')
            .select()
            .eq('product_id', _productId)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();
        _auction = existingAuction;
      } catch (e) {
        debugPrint('Failed to resolve auction row: $e');
      }
    }

    if (_auction == null) {
      return 'Auction record not found for this product.';
    }

    final auctionId = _auction!['auction_id'] as String;

    try {
      final rpcRes = await _supabase.client.rpc(
        'place_bid',
        params: {'p_auction_id': auctionId, 'p_amount': amount},
      );

      if (supabaseRpcSuccess(rpcRes)) {
        await _loadAuctionData();
        _subscribeAuctionRealtime();
        notifyListeners();
        return null;
      }
      return supabaseRpcError(rpcRes, fallback: 'Failed to place bid.');
    } catch (e) {
      debugPrint('ProductDetailController.placeBid error: $e');
      return 'Failed to place bid. Please try again.';
    }
  }

  /// Opens or creates the product-linked thread with this listing's seller.
  Future<({String? conversationId, String? error})>
  openSellerConversation() async {
    final myId = _auth.user?.id;
    final product = _product;
    final sellerId = product?.sellerId;
    if (myId == null) {
      return (
        conversationId: null,
        error: 'Please sign in to message the seller.',
      );
    }
    if (product == null || sellerId == null || sellerId.isEmpty) {
      return (conversationId: null, error: 'Unable to start this chat.');
    }
    if (myId == sellerId) {
      return (conversationId: null, error: 'This is your listing.');
    }
    try {
      final id = await _conversations.openOrCreate(
        myId: myId,
        otherId: sellerId,
        productId: product.id,
      );
      return (conversationId: id, error: null);
    } catch (e) {
      debugPrint('ProductDetailController.openSellerConversation error: $e');
      return (conversationId: null, error: 'Could not open this conversation.');
    }
  }

  /// Pull-to-refresh — re-fetches everything from Supabase.
  Future<void> refresh() => _loadProduct();

  Future<void> reconcileOnResume() async {
    if (!isAuction) return;
    await _closeExpiredAuctions();
    await _loadAuctionData();
    _subscribeAuctionRealtime();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _reloadDebounce?.cancel();
    unawaited(_unsubscribeAuctionRealtime());
    super.dispose();
  }
}
