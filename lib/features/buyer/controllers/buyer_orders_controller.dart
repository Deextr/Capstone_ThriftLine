import 'package:flutter/foundation.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/utils/supabase_rpc.dart';
import '../../../models/order_model.dart';
import '../../../providers/auth_provider.dart';
import '../data/order_query.dart';

class BuyerOrdersController extends ChangeNotifier {
  BuyerOrdersController({
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
  bool _isSavingAddress = false;
  String? _errorMessage;

  List<OrderModel> get orders => _orders;
  OrderModel? get order => _order;
  bool get isLoading => _isLoading;
  bool get isSavingAddress => _isSavingAddress;
  String? get errorMessage => _errorMessage;

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
        if (_order == null) {
          _errorMessage = 'Order not found.';
        }
      } else {
        _orders = await fetchOrdersForBuyer(_supabase, myId);
      }
    } catch (e) {
      debugPrint('BuyerOrdersController.load error: $e');
      _errorMessage = 'Unable to load orders.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<String?> setAddress(String addressId) async {
    final id = orderId ?? _order?.id;
    if (id == null) return 'Order not found.';
    _isSavingAddress = true;
    notifyListeners();
    try {
      final rpcRes = await _supabase.client.rpc(
        'set_order_address',
        params: {'p_order_id': id, 'p_address_id': addressId},
      );
      if (!supabaseRpcSuccess(rpcRes)) {
        return supabaseRpcError(
          rpcRes,
          fallback: 'Could not save that address.',
        );
      }
      await load();
      return null;
    } catch (e) {
      debugPrint('BuyerOrdersController.setAddress error: $e');
      return 'Could not save that address.';
    } finally {
      _isSavingAddress = false;
      notifyListeners();
    }
  }
}
