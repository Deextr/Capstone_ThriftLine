import 'package:flutter/foundation.dart';

import '../../../core/services/supabase_service.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/following_shops_provider.dart';
import '../../chat/data/conversation_service.dart';
import '../data/followed_shop_item.dart';

enum FollowingFilter {
  all('All'),
  hasListings('Active Listings'),
  topRated('Top Rated (4.5+ ★)'),
  highTrust('High trust sellers');

  const FollowingFilter(this.label);
  final String label;
}

/// Feature controller for the Following Shops screen.
///
/// Handles search, category filtering, unfollow actions, and opening
/// conversations with followed sellers.
class FollowingShopsController extends ChangeNotifier {
  FollowingShopsController({
    required SupabaseService supabase,
    AuthProvider? auth,
    FollowingShopsProvider? provider,
    ConversationService? conversations,
  }) : _auth = auth,
       _provider = provider,
       _conversations = conversations ?? ConversationService(supabase) {
    _provider?.addListener(_onProviderUpdated);
  }

  final AuthProvider? _auth;
  final FollowingShopsProvider? _provider;
  final ConversationService _conversations;

  FollowingFilter _filter = FollowingFilter.all;
  String _searchQuery = '';
  bool _isSearching = false;

  FollowingFilter get filter => _filter;
  String get searchQuery => _searchQuery;
  bool get isSearching => _isSearching;
  bool get isLoading => _provider?.isLoading ?? false;
  String? get errorMessage => _provider?.errorMessage;
  int get totalCount => _provider?.followingCount ?? 0;

  void _onProviderUpdated() {
    notifyListeners();
  }

  @override
  void dispose() {
    _provider?.removeListener(_onProviderUpdated);
    super.dispose();
  }

  /// The filtered list of followed shops.
  List<FollowedShopItem> get shops {
    final allShops = _provider?.followedShops ?? const [];
    if (allShops.isEmpty) return const [];

    return allShops.where((shop) {
      // 1. Category filter
      switch (_filter) {
        case FollowingFilter.all:
          break;
        case FollowingFilter.hasListings:
          if (shop.previewProducts.isEmpty && shop.itemCount <= 0) return false;
          break;
        case FollowingFilter.topRated:
          if (shop.rating < 4.5 || shop.ratingCount <= 0) return false;
          break;
        case FollowingFilter.highTrust:
          if (shop.trustScore < 75) return false;
          break;
      }

      // 2. Search query filter
      final q = _searchQuery.trim().toLowerCase();
      if (q.isNotEmpty) {
        final matchesShopName = shop.shopName.toLowerCase().contains(q);
        final matchesUsername = shop.username.toLowerCase().contains(q);
        final matchesOwner = shop.ownerName.toLowerCase().contains(q);
        final matchesLocation = shop.location.toLowerCase().contains(q);
        final matchesBio = shop.shopBio?.toLowerCase().contains(q) ?? false;
        if (!matchesShopName &&
            !matchesUsername &&
            !matchesOwner &&
            !matchesLocation &&
            !matchesBio) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  void setSearchQuery(String query) {
    if (_searchQuery == query) return;
    _searchQuery = query;
    notifyListeners();
  }

  void toggleSearch(bool isSearching) {
    _isSearching = isSearching;
    if (!isSearching && _searchQuery.isNotEmpty) {
      _searchQuery = '';
    }
    notifyListeners();
  }

  void setFilter(FollowingFilter newFilter) {
    if (_filter == newFilter) return;
    _filter = newFilter;
    notifyListeners();
  }

  Future<void> refresh() async {
    await _provider?.refresh();
  }

  Future<bool> toggleFollow(String sellerId) async {
    final res = await _provider?.toggleFollow(sellerId);
    return res ?? false;
  }

  /// Opens or creates a direct conversation thread with the seller.
  Future<({String? conversationId, String? error})> openConversation(
    String sellerId,
  ) async {
    final myId = _auth?.user?.id;
    if (myId == null) {
      return (
        conversationId: null,
        error: 'Please sign in to message this seller.',
      );
    }
    if (sellerId.isEmpty) {
      return (conversationId: null, error: 'Unable to start this chat.');
    }
    if (myId == sellerId) {
      return (conversationId: null, error: 'This is your shop.');
    }
    try {
      final id = await _conversations.openOrCreate(
        myId: myId,
        otherId: sellerId,
      );
      return (conversationId: id, error: null);
    } catch (e) {
      debugPrint('FollowingShopsController.openConversation error: $e');
      return (conversationId: null, error: 'Could not open this conversation.');
    }
  }
}
