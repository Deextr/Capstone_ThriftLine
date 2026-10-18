import 'package:flutter/foundation.dart';

import '../../../core/services/supabase_service.dart';
import '../../../providers/auth_provider.dart';
import '../data/seller_review_service.dart';
import '../domain/seller_product_review_summary.dart';

class SellerProductRatingsController extends ChangeNotifier {
  SellerProductRatingsController({
    required SupabaseService supabase,
    required AuthProvider auth,
    SellerReviewService? reviews,
  }) : _auth = auth,
       _reviews = reviews ?? SellerReviewService(supabase) {
    load();
  }

  final AuthProvider _auth;
  final SellerReviewService _reviews;

  List<SellerProductReviewSummary> _products = [];
  bool _isLoading = true;
  String? _errorMessage;

  List<SellerProductReviewSummary> get products => _products;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get hasError => _errorMessage != null;

  SellerProductReviewSummary? summaryForProduct(String productId) {
    for (final summary in _products) {
      if (summary.productId == productId) return summary;
    }
    return null;
  }

  Future<void> load() async {
    final sellerId = _auth.user?.id;
    if (sellerId == null || sellerId.isEmpty) {
      _errorMessage = 'Sign in as a seller to view product ratings.';
      _isLoading = false;
      notifyListeners();
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _products = await _reviews.loadProductReviewSummaries(sellerId);
      _errorMessage = null;
    } catch (e) {
      debugPrint('SellerProductRatingsController.load error: $e');
      _errorMessage = 'Unable to load product ratings. Please try again.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
