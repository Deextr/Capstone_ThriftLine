import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../domain/product_image_storage.dart';

class SellerListingDeleteService {
  SellerListingDeleteService(this._supabase);

  final SupabaseService _supabase;

  /// Deletes listing photos from Storage, removes image rows, then hard-deletes
  /// the product when allowed. Falls back to `status = removed` when the product
  /// is referenced by orders (FK RESTRICT).
  Future<String?> deleteOwnListing(String productId) async {
    final sellerId = _supabase.currentUser?.id;
    if (sellerId == null) return 'Please sign in.';

    try {
      final row = await _supabase.client
          .from('products')
          .select('product_id, seller_id, product_images(image_url)')
          .eq('product_id', productId)
          .maybeSingle();

      if (row == null) return null;

      if ((row['seller_id'] as String?) != sellerId) {
        return 'You cannot delete this listing.';
      }

      final images = row['product_images'] as List<dynamic>? ?? [];
      final urls = images
          .map((e) => (e as Map<String, dynamic>)['image_url'] as String?)
          .toList();
      final paths = productImageStoragePathsForSeller(
        imageUrls: urls,
        sellerId: sellerId,
      );

      if (paths.isNotEmpty) {
        try {
          await _supabase.client.storage
              .from(productImagesBucket)
              .remove(paths);
        } catch (e, st) {
          debugPrint('SellerListingDeleteService storage remove: $e\n$st');
          return 'Could not delete listing photos. Please try again.';
        }
      }

      await _supabase.client
          .from('product_images')
          .delete()
          .eq('product_id', productId);

      try {
        await _supabase.client
            .from('products')
            .delete()
            .eq('product_id', productId)
            .eq('seller_id', sellerId);
      } on PostgrestException catch (e) {
        if (e.code == '23503') {
          await _supabase.client
              .from('products')
              .update({'status': 'removed'})
              .eq('product_id', productId)
              .eq('seller_id', sellerId);
        } else {
          rethrow;
        }
      }

      return null;
    } catch (e, st) {
      debugPrint('SellerListingDeleteService.deleteOwnListing: $e\n$st');
      return 'Failed to delete listing. Please try again.';
    }
  }
}
