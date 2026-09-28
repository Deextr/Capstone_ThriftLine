import 'package:flutter/foundation.dart';

import '../core/services/supabase_service.dart';
import '../features/buyer/data/catalog_product_query.dart';
import '../models/enums.dart';
import '../models/product_model.dart';

/// Manages saved/favorited items for the authenticated user using Supabase `saved_items`.
class SavedItemsProvider extends ChangeNotifier {
  SavedItemsProvider(this._supabase);

  final SupabaseService _supabase;
  final Set<String> _savedProductIds = {};
  List<ProductModel> _savedProducts = [];
  String? _userId;
  bool _isLoading = false;
  String? _errorMessage;

  Set<String> get savedProductIds => Set.unmodifiable(_savedProductIds);
  List<ProductModel> get savedProducts => List.unmodifiable(_savedProducts);
  int get savedCount => _savedProductIds.length;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  bool isSaved(String productId) => _savedProductIds.contains(productId);

  /// Called when auth state changes or session binds.
  Future<void> startForUser(String? userId) async {
    if (userId == null || userId.isEmpty) {
      _userId = null;
      _savedProductIds.clear();
      _savedProducts = [];
      _isLoading = false;
      _errorMessage = null;
      notifyListeners();
      return;
    }

    if (_userId == userId && _savedProductIds.isNotEmpty) return;

    _userId = userId;
    await refresh();
  }

  /// Reloads saved items from Supabase.
  Future<void> refresh() async {
    final userId = _userId;
    if (userId == null) return;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await runProductCatalogSelect((select) async {
        return await _supabase.client
            .from('saved_items')
            .select('''
            saved_item_id,
            product_id,
            created_at,
            product:products ($select)
          ''')
            .eq('user_id', userId)
            .order('created_at', ascending: false);
      });

      final rows = response as List<dynamic>;
      final extraIds = <String>[];
      for (final row in rows) {
        final productRaw =
            (row as Map<String, dynamic>)['product'] as Map<String, dynamic>?;
        final sellerId = productRaw?['seller_id'] as String?;
        if (sellerId != null) extraIds.add(sellerId);
      }
      final sellerProfilesMap = await fetchSellerProfilesMap(
        _supabase.client,
        extraSellerIds: extraIds,
        includeApproved: false,
      );

      _savedProductIds.clear();
      final List<ProductModel> products = [];

      for (final row in rows) {
        final r = row as Map<String, dynamic>;
        final pId = r['product_id'] as String?;
        if (pId != null) {
          _savedProductIds.add(pId);
        }

        final productRaw = r['product'] as Map<String, dynamic>?;
        if (productRaw != null) {
          final sellerId = productRaw['seller_id'] as String?;
          final p = ProductModel.fromSupabase(
            productRaw,
            sellerProfile: sellerId != null
                ? sellerProfilesMap[sellerId]
                : null,
          );
          // Only show active or sold products
          if (p.status == ProductStatus.active ||
              p.status == ProductStatus.sold) {
            products.add(p);
          }
        }
      }

      _savedProducts = products;
      _errorMessage = null;
    } catch (e) {
      debugPrint('SavedItemsProvider.refresh error: $e');
      _errorMessage = 'Failed to load saved items.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Toggles saved status for a product with optimistic UI update.
  Future<bool> toggleSave(String productId, [ProductModel? product]) async {
    final userId = _userId;
    if (userId == null) return false;

    final wasSaved = _savedProductIds.contains(productId);

    // â”€â”€ Optimistic update â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    if (wasSaved) {
      _savedProductIds.remove(productId);
      _savedProducts = _savedProducts.where((p) => p.id != productId).toList();
    } else {
      _savedProductIds.add(productId);
      if (product != null) {
        _savedProducts = [product, ..._savedProducts];
      }
    }
    notifyListeners();

    // â”€â”€ Supabase mutation â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    try {
      if (wasSaved) {
        await _supabase.client
            .from('saved_items')
            .delete()
            .eq('user_id', userId)
            .eq('product_id', productId);
      } else {
        try {
          await _supabase.client.from('saved_items').insert({
            'user_id': userId,
            'product_id': productId,
          });
        } catch (e) {
          if (!isUniqueViolation(e)) rethrow;
        }

        // If we didn't have the full ProductModel, fetch it
        if (product == null) {
          refresh();
        }
      }
      return true;
    } catch (e) {
      debugPrint('SavedItemsProvider.toggleSave error: $e');

      // Revert optimistic update on failure
      if (wasSaved) {
        _savedProductIds.add(productId);
        if (product != null) {
          _savedProducts = [product, ..._savedProducts];
        }
      } else {
        _savedProductIds.remove(productId);
        _savedProducts = _savedProducts
            .where((p) => p.id != productId)
            .toList();
      }
      notifyListeners();
      return false;
    }
  }
}
