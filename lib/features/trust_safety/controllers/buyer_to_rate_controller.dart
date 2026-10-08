import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
    _subscribeRealtime();
  }

  final SupabaseService _supabase;
  final AuthProvider _auth;
  RealtimeChannel? _channel;
  bool _disposed = false;

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

  void _subscribeRealtime() {
    final myId = _auth.user?.id;
    if (myId == null || myId.isEmpty) return;

    try {
      _channel = _supabase.client
          .channel('buyer-reviews-$myId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'reviews',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'reviewer_id',
              value: myId,
            ),
            callback: (_) => unawaited(load(showSpinner: false)),
          )
          .subscribe();
    } catch (e) {
      debugPrint('BuyerToRateController realtime subscription error: $e');
    }
  }

  Future<void> load({bool showSpinner = true}) async {
    final myId = _auth.user?.id;
    if (myId == null) {
      _orders = [];
      _myReviews = {};
      _isLoading = false;
      _notify();
      return;
    }

    if (showSpinner) {
      _isLoading = true;
      _errorMessage = null;
      _notify();
    }

    try {
      _orders = await fetchOrdersForBuyer(_supabase, myId);
      _myReviews = await fetchMyBuyerReviewsMap(_supabase, myId);
      _errorMessage = null;
    } catch (e) {
      debugPrint('BuyerToRateController.load error: $e');
      _errorMessage = 'Unable to load your reviews.';
    } finally {
      _isLoading = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    final ch = _channel;
    _channel = null;
    if (ch != null) {
      unawaited(_supabase.client.removeChannel(ch));
    }
    super.dispose();
  }
}
