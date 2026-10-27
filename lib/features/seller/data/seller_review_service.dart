import 'package:flutter/foundation.dart';

import '../../../core/services/supabase_service.dart';
import '../../../models/order_model.dart';
import '../../../models/review_model.dart';
import '../../buyer/data/order_query.dart';
import '../../trust_safety/data/review_query.dart';
import '../domain/seller_product_review_summary.dart';

class SellerReviewService {
  SellerReviewService(this._supabase);

  final SupabaseService _supabase;

  Future<List<ReviewModel>> loadShopReviews(String sellerUserId) =>
      fetchShopReviewsForSeller(_supabase, sellerUserId);

  Future<List<SellerProductReviewSummary>> loadProductReviewSummaries(
    String sellerUserId,
  ) async {
    final reviews = await loadShopReviews(sellerUserId);
    if (reviews.isEmpty) return [];

    final orderIds = reviews
        .map((review) => review.orderId)
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    final orderProducts = await _loadOrderProductRefs(
      sellerUserId: sellerUserId,
      orderIds: orderIds,
    );

    return groupReviewsByProduct(
      reviews: reviews,
      orderProducts: orderProducts,
    );
  }

  Future<Map<String, SellerOrderProductRef>> _loadOrderProductRefs({
    required String sellerUserId,
    required List<String> orderIds,
  }) async {
    if (orderIds.isEmpty) return {};

    try {
      final rows = await runOrderSelect((select) {
        return _supabase.client
            .from('orders')
            .select(select)
            .eq('seller_id', sellerUserId)
            .inFilter('order_id', orderIds);
      });

      final out = <String, SellerOrderProductRef>{};
      for (final raw in rows as List<dynamic>) {
        if (raw is! Map<String, dynamic>) continue;
        final order = OrderModel.fromSupabase(raw);
        if (order.sellerId != sellerUserId) continue;
        out[order.id] = SellerOrderProductRef(
          productId: order.productId,
          productTitle: order.productTitle,
          productImageUrl: order.productImage,
        );
      }
      return out;
    } catch (e) {
      debugPrint('SellerReviewService._loadOrderProductRefs error: $e');
      return {};
    }
  }
}
