import 'package:flutter/foundation.dart';

import '../../../core/services/supabase_service.dart';
import '../../../models/review_model.dart';
import '../../../providers/auth_provider.dart';
import '../data/seller_review_service.dart';

class SellerShopRatingsController extends ChangeNotifier {
  SellerShopRatingsController({
    required SupabaseService supabase,
    required AuthProvider auth,
    SellerReviewService? reviews,
  }) : _auth = auth,
       _reviews = reviews ?? SellerReviewService(supabase) {
    load();
  }

  final AuthProvider _auth;
  final SellerReviewService _reviews;

  List<ReviewModel> _shopReviews = [];
  bool _isLoading = true;
  String? _errorMessage;

  List<ReviewModel> get shopReviews => _shopReviews;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get hasError => _errorMessage != null;

  double get averageRating {
    final user = _auth.user;
    final stored = user?.rating;
    if (stored != null && (_auth.user?.ratingCount ?? 0) > 0) {
      return stored;
    }
    if (_shopReviews.isEmpty) return 0;
    final sum = _shopReviews.fold<int>(0, (acc, r) => acc + r.rating);
    return sum / _shopReviews.length;
  }

  int get reviewCount => _auth.user?.ratingCount ?? _shopReviews.length;

  Future<void> load() async {
    final sellerId = _auth.user?.id;
    if (sellerId == null || sellerId.isEmpty) {
      _errorMessage = 'Sign in as a seller to view shop ratings.';
      _isLoading = false;
      notifyListeners();
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _shopReviews = await _reviews.loadShopReviews(sellerId);
      _errorMessage = null;
    } catch (e) {
      debugPrint('SellerShopRatingsController.load error: $e');
      _errorMessage = 'Unable to load shop ratings. Please try again.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
