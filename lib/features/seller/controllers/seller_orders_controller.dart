import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/utils/supabase_rpc.dart';
import '../../../models/order_model.dart';
import '../../../models/review_model.dart';
import '../../../providers/auth_provider.dart';
import '../../buyer/data/order_query.dart';
import '../../trust_safety/data/review_query.dart';
import '../data/seller_order_buckets.dart';

class SellerOrdersController extends ChangeNotifier {
  SellerOrdersController({
    required SupabaseService supabase,
    required AuthProvider auth,
    this.orderId,
  }) : _supabase = supabase,
       _auth = auth {
    _subscribe();
    _lifecycle = AppLifecycleListener(
      onResume: () {
        unawaited(load(showSpinner: false));
      },
    );
    load();
  }

  final SupabaseService _supabase;
  final AuthProvider _auth;
  final String? orderId;

  List<OrderModel> _orders = [];
  OrderModel? _order;
  Map<String, ReviewModel> _myReviews = {};
  bool _isLoading = true;
  bool _isUpdatingDelivery = false;
  String? _errorMessage;
  RealtimeChannel? _channel;
  AppLifecycleListener? _lifecycle;
  bool _disposed = false;

  List<OrderModel> get orders => _orders;
  OrderModel? get order => _order;
  ReviewModel? reviewFor(String orderId) => _myReviews[orderId];
  bool get isLoading => _isLoading;
  bool get isUpdatingDelivery => _isUpdatingDelivery;
  String? get errorMessage => _errorMessage;

  /// Dashboard and nav badge: orders that need the seller to arrange delivery.
  int get pendingCount => countIn(SellerOrderBucket.toShip);

  int countIn(SellerOrderBucket bucket) => sellerOrderCount(_orders, bucket);

  List<OrderModel> ordersIn(SellerOrderBucket bucket) =>
      sellerOrdersInBucket(_orders, bucket);

  Future<void> load({bool showSpinner = true}) async {
    final myId = _auth.user?.id;
    if (myId == null) {
      _orders = [];
      _order = null;
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
      unawaited(_completeExpiredInspections());
      if (orderId != null) {
        _order = await fetchOrderById(_supabase, orderId!, sellerId: myId);
        if (_order == null) _errorMessage = 'Order not found.';
      } else {
        _orders = await fetchOrdersForSeller(_supabase, myId);
      }
      await _loadMyReviews(myId);
    } catch (e) {
      debugPrint('SellerOrdersController.load error: $e');
      _errorMessage = 'Unable to load orders.';
    } finally {
      _isLoading = false;
      _notify();
    }
  }

  Future<void> _completeExpiredInspections() async {
    try {
      await _supabase.client.rpc('complete_expired_inspections');
    } catch (e) {
      debugPrint('complete_expired_inspections error: $e');
    }
  }

  Future<String?> assignRider({
    required String riderName,
    required String riderPhone,
    required String vehicleType,
    String? plateNumber,
    DateTime? estimatedDeliveryAt,
    String? deliveryNotes,
  }) {
    return _runDeliveryRpc('assign_freelance_rider', {
      'p_order_id': orderId ?? _order?.id,
      'p_rider_name': riderName,
      'p_rider_phone': riderPhone,
      'p_vehicle_type': vehicleType,
      'p_plate_number': plateNumber,
      'p_estimated_delivery_at': estimatedDeliveryAt?.toUtc().toIso8601String(),
      'p_delivery_notes': deliveryNotes,
    }, fallback: 'Could not save rider details.');
  }

  Future<String?> advanceDelivery(String action) {
    return _runDeliveryRpc('advance_delivery', {
      'p_order_id': orderId ?? _order?.id,
      'p_action': action,
    }, fallback: 'Could not update delivery status.');
  }

  Future<String?> verifyDeliveryPin(String pin) {
    return _runDeliveryRpc('verify_delivery_pin', {
      'p_order_id': orderId ?? _order?.id,
      'p_delivery_pin': pin,
    }, fallback: 'Could not verify the Delivery PIN.');
  }

  Future<String?> markDeliveryFailed(String reason) {
    return _runDeliveryRpc('mark_delivery_failed', {
      'p_order_id': orderId ?? _order?.id,
      'p_reason': reason,
    }, fallback: 'Could not record the delivery problem.');
  }

  Future<String?> _runDeliveryRpc(
    String name,
    Map<String, dynamic> params, {
    required String fallback,
  }) async {
    final id = params['p_order_id']?.toString();
    if (id == null || id.isEmpty) return 'Order not found.';
    if (_isUpdatingDelivery) return null;
    _isUpdatingDelivery = true;
    _notify();
    try {
      final rpcRes = await _supabase.client.rpc(name, params: params);
      if (!supabaseRpcSuccess(rpcRes)) {
        return supabaseRpcError(rpcRes, fallback: fallback);
      }
      await load(showSpinner: false);
      return null;
    } catch (e) {
      debugPrint('$name error: $e');
      return fallback;
    } finally {
      _isUpdatingDelivery = false;
      _notify();
    }
  }

  Future<void> _loadMyReviews(String myId) async {
    final ids = <String>{
      if (_order != null && _order!.isCompleted) _order!.id,
      for (final order in _orders)
        if (order.isCompleted) order.id,
    };
    _myReviews = await fetchMyReviewsForOrders(_supabase, myId, ids);
  }

  void _subscribe() {
    final myId = _auth.user?.id;
    if (myId == null) return;
    try {
      final channelName = orderId != null
          ? 'seller-order-$orderId'
          : 'seller-orders-$myId';
      _channel = _supabase.client
          .channel(channelName)
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'orders',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: orderId != null ? 'order_id' : 'seller_id',
              value: orderId ?? myId,
            ),
            callback: (_) => unawaited(load(showSpinner: false)),
          )
          .subscribe();
    } catch (e) {
      debugPrint('SellerOrdersController realtime error: $e');
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _lifecycle?.dispose();
    final channel = _channel;
    _channel = null;
    if (channel != null) {
      unawaited(_supabase.client.removeChannel(channel));
    }
    super.dispose();
  }
}
