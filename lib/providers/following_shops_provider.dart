import 'package:flutter/foundation.dart';

import '../core/services/supabase_service.dart';
import '../features/buyer/data/catalog_product_query.dart';
import '../features/profile/data/followed_shop_item.dart';
import '../models/product_model.dart';
import '../models/seller_profile.dart';

/// Manages followed shops for the authenticated user using Supabase `follows`.
class FollowingShopsProvider extends ChangeNotifier {
  FollowingShopsProvider(this._supabase);

  final SupabaseService _supabase;
  final Set<String> _followingSellerIds = {};
  List<FollowedShopItem> _followedShops = [];
  String? _userId;
  bool _isLoading = false;
  String? _errorMessage;

  Set<String> get followingSellerIds => Set.unmodifiable(_followingSellerIds);
  List<FollowedShopItem> get followedShops => List.unmodifiable(_followedShops);
  int get followingCount => _followingSellerIds.length;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  bool isFollowing(String sellerId) => _followingSellerIds.contains(sellerId);

  /// Called when auth state changes or session binds.
  Future<void> startForUser(String? userId) async {
    if (userId == null || userId.isEmpty) {
      _userId = null;
      _followingSellerIds.clear();
      _followedShops = [];
      _isLoading = false;
      _errorMessage = null;
      notifyListeners();
      return;
    }

    if (_userId == userId && _followingSellerIds.isNotEmpty) return;

    _userId = userId;
    await refresh();
  }

  /// Reloads followed shops from Supabase.
  Future<void> refresh() async {
    final userId = _userId;
    if (userId == null) return;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // 1. Fetch followed seller IDs
      final followRows = await _supabase.client
          .from('follows')
          .select('following_id, created_at')
          .eq('follower_id', userId)
          .order('created_at', ascending: false);

      final rows = followRows as List<dynamic>;
      final followingIds = <String>[];
      final followedAtMap = <String, DateTime>{};

      for (final r in rows) {
        final map = r as Map<String, dynamic>;
        final followingId = map['following_id'] as String?;
        if (followingId != null && followingId != userId) {
          followingIds.add(followingId);
          final createdAt = map['created_at'] != null
              ? DateTime.tryParse(map['created_at'] as String)
              : null;
          if (createdAt != null) {
            followedAtMap[followingId] = createdAt;
          }
        }
      }

      _followingSellerIds
        ..clear()
        ..addAll(followingIds);

      if (followingIds.isEmpty) {
        _followedShops = [];
        _errorMessage = null;
        _isLoading = false;
        notifyListeners();
        return;
      }

      // 2. Fetch hydrated seller profiles
      final sellerProfilesMap = await fetchSellerProfilesMap(
        _supabase.client,
        extraSellerIds: followingIds,
        includeApproved: false,
      );

      // 3. Fetch active preview products for these sellers
      List<ProductModel> products = [];
      try {
        final productsResponse = await runProductCatalogSelect((select) async {
          return await _supabase.client
              .from('products')
              .select(select)
              .inFilter('seller_id', followingIds)
              .eq('status', 'active')
              .order('created_at', ascending: false);
        });

        products = hydrateCatalogProducts(
          productsResponse as List<dynamic>,
          sellerProfilesMap,
        );
      } catch (e) {
        debugPrint('FollowingShopsProvider products preview error: $e');
      }

      final productsBySeller = <String, List<ProductModel>>{};
      for (final p in products) {
        final sid = p.sellerId;
        if (sid != null && sid.isNotEmpty) {
          productsBySeller.putIfAbsent(sid, () => []).add(p);
        }
      }

      // 4. Construct FollowedShopItem list maintaining follow order
      final items = <FollowedShopItem>[];
      for (final sellerId in followingIds) {
        final profileRow = sellerProfilesMap[sellerId];
        if (profileRow != null) {
          final sellerProfile = SellerProfile.fromSupabase(
            profileRow,
            activeProductCount: productsBySeller[sellerId]?.length,
          );
          items.add(
            FollowedShopItem(
              profile: sellerProfile,
              previewProducts: (productsBySeller[sellerId] ?? [])
                  .take(4)
                  .toList(),
              followedAt: followedAtMap[sellerId],
            ),
          );
        }
      }

      _followedShops = items;
      _errorMessage = null;
    } catch (e) {
      debugPrint('FollowingShopsProvider.refresh error: $e');
      _errorMessage = 'Failed to load following shops.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Toggles follow status for a seller with optimistic UI updates.
  Future<bool> toggleFollow(String sellerId, [SellerProfile? profile]) async {
    final userId = _userId;
    if (userId == null || userId == sellerId) return false;

    final wasFollowing = _followingSellerIds.contains(sellerId);
    FollowedShopItem? removedItem;
    int? removedIndex;

    // Optimistic state update
    if (wasFollowing) {
      _followingSellerIds.remove(sellerId);
      final idx = _followedShops.indexWhere((s) => s.sellerId == sellerId);
      if (idx != -1) {
        removedIndex = idx;
        removedItem = _followedShops[idx];
        _followedShops = List.of(_followedShops)..removeAt(idx);
      }
    } else {
      _followingSellerIds.add(sellerId);
      if (profile != null) {
        _followedShops = [
          FollowedShopItem(profile: profile),
          ..._followedShops,
        ];
      }
    }
    notifyListeners();

    try {
      if (wasFollowing) {
        await _supabase.client
            .from('follows')
            .delete()
            .eq('follower_id', userId)
            .eq('following_id', sellerId);
      } else {
        try {
          await _supabase.client.from('follows').insert({
            'follower_id': userId,
            'following_id': sellerId,
          });
        } catch (e) {
          if (!isUniqueViolation(e)) rethrow;
        }
      }
      return true;
    } catch (e) {
      debugPrint('FollowingShopsProvider.toggleFollow error: $e');
      // Rollback
      if (wasFollowing) {
        _followingSellerIds.add(sellerId);
        if (removedItem != null && removedIndex != null) {
          final list = List.of(_followedShops);
          if (removedIndex <= list.length) {
            list.insert(removedIndex, removedItem);
          } else {
            list.add(removedItem);
          }
          _followedShops = list;
        }
      } else {
        _followingSellerIds.remove(sellerId);
        _followedShops = _followedShops
            .where((s) => s.sellerId != sellerId)
            .toList();
      }
      notifyListeners();
      return false;
    }
  }

  /// Externally synchronizes a follow state without full re-fetch.
  void syncFollowState(
    String sellerId,
    bool isFollowing, [
    SellerProfile? profile,
  ]) {
    if (isFollowing) {
      _followingSellerIds.add(sellerId);
      if (profile != null &&
          !_followedShops.any((s) => s.sellerId == sellerId)) {
        _followedShops = [
          FollowedShopItem(profile: profile),
          ..._followedShops,
        ];
      }
    } else {
      _followingSellerIds.remove(sellerId);
      _followedShops = _followedShops
          .where((s) => s.sellerId != sellerId)
          .toList();
    }
    notifyListeners();
  }
}
