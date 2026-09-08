import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/services/supabase_service.dart';
import '../../../../models/bid_model.dart';
import '../../../../models/enums.dart';
import '../../../../models/product_model.dart';
import '../../../../providers/auth_provider.dart';

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

  /// Fetches all bids placed by the authenticated buyer from Supabase,
  /// joining corresponding auctions and products.
  Future<void> loadBids() async {
    final userId = _auth.user?.id;
    if (userId == null) {
      _isLoading = false;
      _allBids = [];
      notifyListeners();
      return;
    }

    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

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

      _allBids = auctionBidsMap.values.toList();
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      debugPrint('BuyerBidsController.loadBids error: $e');
      _error = 'Failed to load your bids. Please try again.';
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Places or raises a bid on an auction.
  ///
  /// Uses the atomic `place_bid` RPC function if available, with a resilient
  /// fallback to direct table insertion.
  Future<bool> raiseBid({
    required String auctionId,
    required double amount,
  }) async {
    final userId = _auth.user?.id;
    if (userId == null) return false;

    // 1. Try atomic place_bid RPC
    try {
      final rpcRes = await _supabase.client.rpc(
        'place_bid',
        params: {'p_auction_id': auctionId, 'p_amount': amount},
      );

      if (rpcRes is Map && rpcRes['success'] == true) {
        await loadBids();
        return true;
      }
    } catch (e) {
      debugPrint('place_bid RPC error or missing: $e');
    }

    // 2. Fallback: direct insert into bids
    try {
      await _supabase.client.from('bids').insert({
        'auction_id': auctionId,
        'bidder_id': userId,
        'bid_amount': amount,
        'is_highest_bid': true,
      });

      // Best effort update on other bids & auction
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

      await loadBids();
      return true;
    } catch (e) {
      debugPrint('Fallback raiseBid failed: $e');
      return false;
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

  /// Sets up real-time listener on the `bids` table so any outbid or new bid
  /// automatically refreshes the buyer's bids list.
  void _setupRealtimeSubscription() {
    try {
      _bidsSubscription = _supabase.client
          .channel('public:bids:user_${_auth.user?.id ?? "guest"}')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'bids',
            callback: (_) => loadBids(),
          )
          .subscribe();
    } catch (e) {
      debugPrint('Realtime bids subscription error: $e');
    }
  }

  /// Pull-to-refresh helper.
  Future<void> refresh() => loadBids();

  @override
  void dispose() {
    _bidsSubscription?.unsubscribe();
    super.dispose();
  }
}
