import 'package:flutter/foundation.dart';

import '../core/services/supabase_service.dart';
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
      // 1. Fetch seller profiles to map shop names / verified badges
      final Map<String, Map<String, dynamic>> sellerProfilesMap = {};
      try {
        final spResponse = await _supabase.client
            .from('seller_profiles')
            .select('*, user:user_public_profiles(*)');

        final spRows = spResponse as List<dynamic>;
        for (final sp in spRows) {
          if (sp is Map<String, dynamic> && sp['seller_id'] != null) {
            sellerProfilesMap[sp['seller_id'] as String] = sp;
          }
        }
      } catch (e) {
        debugPrint('SavedItemsProvider: seller_profiles fetch error ($e)');
      }

      // 2. Fetch saved_items joined with product details
      final response = await _supabase.client
          .from('saved_items')
          .select('''
            saved_item_id,
            product_id,
            created_at,
            product:products (
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
              )
            )
          ''')
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      final rows = response as List<dynamic>;
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
            sellerProfile: sellerId != null ? sellerProfilesMap[sellerId] : null,
          );
          // Only show active or sold products
          if (p.status == ProductStatus.active || p.status == ProductStatus.sold) {
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
        await _supabase.client.from('saved_items').insert({
          'user_id': userId,
          'product_id': productId,
        });

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
        _savedProducts = _savedProducts.where((p) => p.id != productId).toList();
      }
      notifyListeners();
      return false;
    }
  }
}
