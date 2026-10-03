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

/// Keeps every live [SellerOrdersController] for a seller in sync when one
/// instance confirms an order change (detail vs list use separate providers).
final class SellerOrdersPeerHub {
  SellerOrdersPeerHub._();

  static final Map<String, Set<SellerOrdersController>> _bySeller = {};

  static void register(String sellerId, SellerOrdersController controller) {
    _bySeller.putIfAbsent(sellerId, () => {}).add(controller);
  }

  static void unregister(String sellerId, SellerOrdersController controller) {
    _bySeller[sellerId]?.remove(controller);
    if (_bySeller[sellerId]?.isEmpty ?? false) {
      _bySeller.remove(sellerId);
    }
  }

  static void refreshPeers(String sellerId, SellerOrdersController source) {
    for (final peer in _bySeller[sellerId] ?? {}) {
      if (identical(peer, source) || peer._disposed) continue;
      unawaited(peer.load(showSpinner: false));
    }
  }
}

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
  int _loadGeneration = 0;
  String? _peerSellerId;
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
    final generation = ++_loadGeneration;
    _bindPeerHub(myId);
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
        final fetched = await fetchOrderById(
          _supabase,
          orderId!,
          sellerId: myId,
        );
        if (generation != _loadGeneration) return;
        _order = fetched;
        if (_order == null) _errorMessage = 'Order not found.';
      } else {
        _orders = await fetchOrdersForSeller(_supabase, myId);
        if (generation != _loadGeneration) return;
      }
      await _loadMyReviews(myId);
    } catch (e) {
      debugPrint('SellerOrdersController.load error: $e');
      if (generation == _loadGeneration) {
        _errorMessage = 'Unable to load orders.';
      }
    } finally {
      if (generation == _loadGeneration) {
        _isLoading = false;
        _notify();
      }
    }
  }

  void _bindPeerHub(String? sellerId) {
    if (sellerId == null || sellerId.isEmpty) return;
    if (_peerSellerId == sellerId) return;
    if (_peerSellerId != null) {
      SellerOrdersPeerHub.unregister(_peerSellerId!, this);
    }
    _peerSellerId = sellerId;
    SellerOrdersPeerHub.register(sellerId, this);
  }

  void _refreshPeerControllers() {
    final sellerId = _peerSellerId ?? _auth.user?.id;
    if (sellerId == null || sellerId.isEmpty) return;
    SellerOrdersPeerHub.refreshPeers(sellerId, this);
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

  Future<String?> arrangeReturnRider({
    required String riderName,
    required String riderPhone,
    required String vehicleType,
    String? plateNumber,
    DateTime? pickupScheduledAt,
    String? returnNotes,
  }) {
    return _runDeliveryRpc('arrange_return_rider', {
      'p_order_id': orderId ?? _order?.id,
      'p_rider_name': riderName,
      'p_rider_phone': riderPhone,
      'p_vehicle_type': vehicleType,
      'p_plate_number': plateNumber,
      'p_pickup_scheduled_at': pickupScheduledAt?.toUtc().toIso8601String(),
      'p_return_notes': returnNotes,
    }, fallback: 'Could not save the return rider.');
  }

  Future<String?> confirmReturnReceived() {
    return _runDeliveryRpc('confirm_return_received', {
      'p_order_id': orderId ?? _order?.id,
    }, fallback: 'Could not confirm this return.');
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

  Future<String?> markDeliveryFailed({
    required String reason,
    String? details,
  }) {
    return _runDeliveryRpc('mark_delivery_failed', {
      'p_order_id': orderId ?? _order?.id,
      'p_reason': reason,
      if (details != null) 'p_details': details,
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
      _refreshPeerControllers();
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
      var channel = _supabase.client.channel(channelName);
      channel = channel.onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'orders',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: orderId != null ? 'order_id' : 'seller_id',
          value: orderId ?? myId,
        ),
        callback: (_) => unawaited(load(showSpinner: false)),
      );
      if (orderId != null) {
        channel = channel.onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'shipments',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'order_id',
            value: orderId!,
          ),
          callback: (_) => unawaited(load(showSpinner: false)),
        );
      }
      _channel = channel.subscribe();
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
    if (_peerSellerId != null) {
      SellerOrdersPeerHub.unregister(_peerSellerId!, this);
      _peerSellerId = null;
    }
    _lifecycle?.dispose();
    final channel = _channel;
    _channel = null;
    if (channel != null) {
      unawaited(_supabase.client.removeChannel(channel));
    }
    super.dispose();
  }
}
