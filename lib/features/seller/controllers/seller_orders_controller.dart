import 'package:flutter/foundation.dart';

import '../../../core/services/supabase_service.dart';
import '../../../models/order_model.dart';
import '../../../providers/auth_provider.dart';
import '../../buyer/data/order_query.dart';

class SellerOrdersController extends ChangeNotifier {
  SellerOrdersController({
    required SupabaseService supabase,
    required AuthProvider auth,
    this.orderId,
  }) : _supabase = supabase,
       _auth = auth {
    load();
  }

  final SupabaseService _supabase;
  final AuthProvider _auth;
  final String? orderId;

  List<OrderModel> _orders = [];
  OrderModel? _order;
  bool _isLoading = true;
  String? _errorMessage;

  List<OrderModel> get orders => _orders;
  OrderModel? get order => _order;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  int get pendingCount => _orders.where((o) => o.isPaymentPending).length;

  Future<void> load() async {
    final myId = _auth.user?.id;
    if (myId == null) {
      _orders = [];
      _order = null;
      _isLoading = false;
      notifyListeners();
      return;
    }
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      if (orderId != null) {
        _order = await fetchOrderById(_supabase, orderId!);
        if (_order == null) _errorMessage = 'Order not found.';
      } else {
        _orders = await fetchOrdersForSeller(_supabase, myId);
      }
    } catch (e) {
      debugPrint('SellerOrdersController.load error: $e');
      _errorMessage = 'Unable to load orders.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
