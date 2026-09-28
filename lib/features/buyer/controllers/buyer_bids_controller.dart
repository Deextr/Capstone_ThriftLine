import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/services/supabase_service.dart';
import '../../../../core/utils/supabase_rpc.dart';
import '../../../../models/bid_model.dart';
import '../../../../models/enums.dart';
import '../../../../models/product_model.dart';
import '../../../../providers/auth_provider.dart';
import '../data/catalog_product_query.dart';

/// Controller for managing the buyer's active, won, and lost auction bids.
///
/// Follows the Feature-First MVC architecture guidelines in `AGENTS.md`.
class BuyerBidsController extends ChangeNotifier {
  BuyerBidsController({
    required SupabaseService supabase,
    required AuthProvider auth,
  }) : _supabase = supabase,
       _auth = auth {
    _init();
  }

  final SupabaseService _supabase;
  final AuthProvider _auth;

  bool _isLoading = true;
  String? _error;
  List<UserBid> _allBids = [];
  RealtimeChannel? _bidsSubscription;
  Timer? _reloadDebounce;
  bool _disposed = false;

  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Active bids (winning or currently outbid while the auction is ongoing)
  List<UserBid> get activeBids => _allBids
      .where(
        (b) =>
            b.status == BidStatus.winning ||
            b.status == BidStatus.outbid ||
            b.status == BidStatus.active,
      )
      .toList();

  /// Won bids (auction ended and current user is winner)
  List<UserBid> get wonBids =>
      _allBids.where((b) => b.status == BidStatus.won).toList();

  /// Lost bids (auction ended and another bidder won)
  List<UserBid> get lostBids =>
      _allBids.where((b) => b.status == BidStatus.lost).toList();

  int get activeBidsCount => activeBids.length;
  int get wonBidsCount => wonBids.length;
  int get lostBidsCount => lostBids.length;

  List<UserBid> bidsForTab(BidTab tab) {
    switch (tab) {
      case BidTab.active:
        return activeBids;
      case BidTab.won:
        return wonBids;
      case BidTab.lost:
        return lostBids;
    }
  }

  void _init() {
    loadBids();
    _setupRealtimeSubscription();
  }

  Future<void> _closeExpiredAuctions() async {
    try {
      await _supabase.client.rpc('close_auctions');
    } catch (e) {
      debugPrint('BuyerBidsController.close_auctions: $e');
    }
  }

  /// Fetches this buyer's bids from `v_user_bids` (authoritative status),
  /// falling back to a nested `bids` select if the view is not applied yet.
  ///
  /// [showLoading] is only used for the first load / pull-to-refresh so a
  /// Realtime or post-bid refresh does not replace the list with a skeleton
  /// while a Raise Bid sheet is still open.
  Future<void> loadBids({
    bool showLoading = true,
    bool settleExpired = true,
  }) async {
    final userId = _auth.user?.id;
    if (userId == null) {
      _isLoading = false;
      _allBids = [];
      if (!_disposed) notifyListeners();
      return;
    }

    try {
      final shouldShowLoading = showLoading && _allBids.isEmpty;
      if (shouldShowLoading) {
        _isLoading = true;
        _error = null;
        notifyListeners();
      }

      if (settleExpired) {
        await _closeExpiredAuctions();
      }

      try {
        _allBids = await _loadFromUserBidsView(userId);
      } catch (e) {
        debugPrint('BuyerBidsController v_user_bids fallback: $e');
        _allBids = await _loadFromNestedBids(userId);
      }

      _isLoading = false;
      if (!_disposed) notifyListeners();
    } catch (e) {
      debugPrint('BuyerBidsController.loadBids error: $e');
      _error = 'Failed to load your bids. Please try again.';
      _isLoading = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<List<UserBid>> _loadFromUserBidsView(String userId) async {
    final response = await _supabase.client
        .from('v_user_bids')
        .select()
        .eq('bidder_id', userId)
        .order('created_at', ascending: false);

    final rows = List<Map<String, dynamic>>.from(
      (response as List).map((e) => e as Map<String, dynamic>),
    );
    final products = await _hydrateProducts(
      rows
          .map((row) => row['product_id'] as String?)
          .whereType<String>()
          .where((id) => id.isNotEmpty),
    );

    return rows.map((row) {
      final productId = row['product_id'] as String? ?? '';
      return UserBid.fromSupabase(row, product: products[productId]);
    }).toList();
  }

  Future<List<UserBid>> _loadFromNestedBids(String userId) async {
    final response = await _supabase.client
        .from('bids')
        .select('''
            bid_id,
            auction_id,
            bidder_id,
            bid_amount,
            is_highest_bid,
            created_at,
            auction:auctions!bids_auction_id_fkey (
              auction_id,
              product_id,
              starting_price,
              minimum_increment,
              current_price,
              winner_id,
              starts_at,
              ends_at,
              status,
              product:products!auctions_product_id_fkey (
                product_id,
                seller_id,
                name,
                description,
                price,
                condition,
                listing_type,
                created_at,
                images:product_images (
                  image_url,
                  is_primary,
                  display_order
                ),
                seller:users!products_seller_id_fkey (
                  user_id,
                  username,
                  full_name,
                  avatar
                )
              )
            )
          ''')
        .eq('bidder_id', userId)
        .order('created_at', ascending: false);

    final Map<String, UserBid> auctionBidsMap = {};

    for (final row in response as List) {
      final map = row as Map<String, dynamic>;
      final auctionMap = map['auction'] as Map<String, dynamic>?;
      if (auctionMap == null) continue;
      final auctionId = auctionMap['auction_id'] as String? ?? '';
      if (auctionId.isEmpty) continue;

      final parsedBid = UserBid.fromSupabase(map);
      if (auctionBidsMap.containsKey(auctionId)) {
        if (parsedBid.amount > auctionBidsMap[auctionId]!.amount) {
          auctionBidsMap[auctionId] = parsedBid;
        }
      } else {
        auctionBidsMap[auctionId] = parsedBid;
      }
    }

    return auctionBidsMap.values.toList();
  }

  Future<Map<String, ProductModel>> _hydrateProducts(
    Iterable<String> productIds,
  ) async {
    final ids = productIds.toSet().toList();
    if (ids.isEmpty) return {};

    final rows = await runProductCatalogSelect((select) async {
      return await _supabase.client
          .from('products')
          .select(select)
          .inFilter('product_id', ids);
    });

    final list = rows as List;
    final sellerIds = list
        .map((row) => (row as Map)['seller_id'] as String?)
        .whereType<String>();
    final sellerProfiles = await fetchSellerProfilesMap(
      _supabase.client,
      extraSellerIds: sellerIds,
      includeApproved: false,
    );
    final products = hydrateCatalogProducts(list, sellerProfiles);
    return {for (final product in products) product.id: product};
  }

  /// Latest server price/increment for an auction. Used by Raise Bid so the
  /// sheet is not validated against a stale My Bids snapshot.
  Future<AuctionBidQuote?> fetchAuctionQuote(String auctionId) async {
    if (auctionId.isEmpty) return null;
    try {
      final row = await _supabase.client
          .from('auctions')
          .select('current_price, minimum_increment, status, ends_at')
          .eq('auction_id', auctionId)
          .maybeSingle();
      if (row == null) return null;
      return AuctionBidQuote(
        currentPrice: (row['current_price'] as num?)?.toDouble() ?? 0,
        minimumIncrement: (row['minimum_increment'] as num?)?.toDouble() ?? 0,
        status: row['status'] as String? ?? 'active',
        endsAt: row['ends_at'] != null
            ? DateTime.tryParse(row['ends_at'] as String)
            : null,
      );
    } catch (e) {
      debugPrint('BuyerBidsController.fetchAuctionQuote error: $e');
      return null;
    }
  }

  /// Places or raises a bid on an auction through `place_bid` only.
  ///
  /// Returns `null` on success, or an error message. Does not wait for the
  /// bids list to reload — that refresh is quiet and happens after return.
  Future<String?> raiseBid({
    required String auctionId,
    required double amount,
  }) async {
    if (_auth.user?.id == null) {
      return 'Please sign in to place a bid.';
    }
    if (auctionId.isEmpty) {
      return 'Auction record not found.';
    }

    try {
      final rpcRes = await _supabase.client.rpc(
        'place_bid',
        params: {'p_auction_id': auctionId, 'p_amount': amount},
      );

      if (supabaseRpcSuccess(rpcRes)) {
        unawaited(loadBids(showLoading: false, settleExpired: false));
        return null;
      }
      return supabaseRpcError(rpcRes, fallback: 'Failed to place bid.');
    } catch (e) {
      debugPrint('place_bid RPC error: $e');
      return 'Failed to place bid. Please try again.';
    }
  }

  /// Fetches complete public bid history for a specific auction.
  Future<List<BidEntry>> fetchAuctionBids(String auctionId) async {
    try {
      final res = await _supabase.client
          .from('bids')
          .select('''
            bid_id,
            bid_amount,
            created_at,
            bidder:users!bids_bidder_id_fkey (
              user_id,
              username
            )
          ''')
          .eq('auction_id', auctionId)
          .order('bid_amount', ascending: false);

      return (res as List).map((b) {
        final map = b as Map<String, dynamic>;
        final bidder = map['bidder'] as Map<String, dynamic>?;
        return BidEntry(
          id: map['bid_id'] as String? ?? '',
          username: bidder?['username'] as String? ?? 'Anonymous',
          amount: (map['bid_amount'] as num?)?.toDouble() ?? 0.0,
          createdAt: map['created_at'] != null
              ? DateTime.tryParse(map['created_at'] as String) ?? DateTime.now()
              : DateTime.now(),
        );
      }).toList();
    } catch (e) {
      debugPrint('fetchAuctionBids error: $e');
      return [];
    }
  }

  void _setupRealtimeSubscription() {
    try {
      _bidsSubscription = _supabase.client
          .channel('public:bids:user_${_auth.user?.id ?? "guest"}')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'bids',
            callback: (_) => _scheduleReload(),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'auctions',
            callback: (_) => _scheduleReload(),
          )
          .subscribe();
    } catch (e) {
      debugPrint('Realtime bids subscription error: $e');
    }
  }

  void _scheduleReload() {
    _reloadDebounce?.cancel();
    _reloadDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!_disposed) {
        loadBids(showLoading: false, settleExpired: false);
      }
    });
  }

  /// Pull-to-refresh helper.
  Future<void> refresh() => loadBids();

  /// Pending order created by close_auctions / ensure_auction_order.
  Future<String?> orderIdForWonAuction(String auctionId) async {
    if (auctionId.isEmpty) return null;
    try {
      await _supabase.client.rpc('close_auctions');
    } catch (e) {
      debugPrint('orderIdForWonAuction close_auctions: $e');
    }
    try {
      final row = await _supabase.client
          .from('orders')
          .select('order_id')
          .eq('auction_id', auctionId)
          .maybeSingle();
      return row?['order_id'] as String?;
    } catch (e) {
      debugPrint('orderIdForWonAuction error: $e');
      return null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _reloadDebounce?.cancel();
    _bidsSubscription?.unsubscribe();
    super.dispose();
  }
}
