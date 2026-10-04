import 'package:flutter/foundation.dart';

import '../../../core/services/supabase_service.dart';
import '../../../models/order_model.dart';
import '../../../models/review_model.dart';
import '../../../providers/auth_provider.dart';
import '../../buyer/data/order_query.dart';
import '../data/buyer_to_rate_buckets.dart';
import '../data/review_query.dart';

class BuyerToRateController extends ChangeNotifier {
  BuyerToRateController({
    required SupabaseService supabase,
    required AuthProvider auth,
  }) : _supabase = supabase,
       _auth = auth {
    load();
  }

  final SupabaseService _supabase;
  final AuthProvider _auth;

  List<OrderModel> _orders = [];
  Map<String, ReviewModel> _myReviews = {};
  bool _isLoading = true;
  String? _errorMessage;

  List<OrderModel> get pendingOrders =>
      ordersPendingBuyerReview(_orders, _myReviews);

  List<BuyerRatedPurchase> get ratedPurchases =>
      buyerReviewHistory(_orders, _myReviews);

  int get pendingCount => pendingOrders.length;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> load() async {
    final myId = _auth.user?.id;
    if (myId == null) {
      _orders = [];
      _myReviews = {};
      _isLoading = false;
      notifyListeners();
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _orders = await fetchOrdersForBuyer(_supabase, myId);
      final completedIds = completedOrdersEligibleForBuyerReview(
        _orders,
      ).map((order) => order.id).toList();
      _myReviews = await fetchMyReviewsForOrders(_supabase, myId, completedIds);
    } catch (e) {
      debugPrint('BuyerToRateController.load error: $e');
      _errorMessage = 'Unable to load your reviews.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
