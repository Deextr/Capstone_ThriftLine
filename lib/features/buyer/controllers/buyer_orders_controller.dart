import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/utils/ph_phone.dart';
import '../../../core/utils/supabase_rpc.dart';
import '../../../models/address_model.dart';
import '../../../models/order_model.dart';
import '../../../models/review_model.dart';
import '../../../providers/auth_provider.dart';
import '../../profile/data/address_service.dart';
import '../../trust_safety/data/review_query.dart';
import '../data/order_query.dart';
import '../data/paymongo_checkout.dart';

class BuyerOrdersController extends ChangeNotifier {
  BuyerOrdersController({
    required SupabaseService supabase,
    required AuthProvider auth,
    this.orderId,
  }) : _supabase = supabase,
       _auth = auth {
    _subscribe();
    _lifecycle = AppLifecycleListener(
      onResume: () {
        unawaited(_refreshAfterResume());
      },
    );
    load();
  }

  final SupabaseService _supabase;
  final AuthProvider _auth;
  final String? orderId;

  List<OrderModel> _orders = [];
  OrderModel? _order;
  List<OrderModel> _paymentGroup = [];
  Map<String, ReviewModel> _myReviews = {};
  bool _isLoading = true;
  bool _isSavingAddress = false;
  bool _isStartingPayment = false;
  bool _isConfirmingPayment = false;
  bool _isAbandoning = false;
  bool _isUpdatingDelivery = false;
  String? _errorMessage;
  String? _unsuccessfulOutcome;
  String? _deliveryPin;
  RealtimeChannel? _channel;
  AppLifecycleListener? _lifecycle;
  Timer? _returnPoll;
  bool _disposed = false;

  List<OrderModel> get orders => _orders;
  List<OrderModel> get awaitingPayment => buyerAwaitingPayment(_orders);
  OrderModel? get order => _order;
  List<OrderModel> get paymentGroup {
    if (_paymentGroup.isNotEmpty) return List.unmodifiable(_paymentGroup);
    final current = _order;
    return current == null ? const [] : [current];
  }

  double get paymentGroupTotal =>
      paymentGroup.fold<double>(0, (sum, order) => sum + order.total);
  ReviewModel? reviewFor(String orderId) => _myReviews[orderId];
  bool get isLoading => _isLoading;
  bool get isSavingAddress => _isSavingAddress;
  bool get isStartingPayment => _isStartingPayment;
  bool get isConfirmingPayment => _isConfirmingPayment;
  bool get isAbandoning => _isAbandoning;
  bool get isUpdatingDelivery => _isUpdatingDelivery;
  String? get errorMessage => _errorMessage;
  String? get deliveryPin => _deliveryPin;
  bool get isExpiredPayment =>
      _unsuccessfulOutcome == 'expired' || (_order?.isExpiredCheckout ?? false);

  Future<void> load({bool showSpinner = true}) async {
    final myId = _auth.user?.id;
    if (myId == null) {
      _orders = [];
      _order = null;
      _paymentGroup = [];
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
      if (orderId == null) {
        await restoreAbandonedFixedPriceCheckouts(_supabase);
        await syncMyUnpaidCheckouts(_supabase);
      }
      if (orderId != null) {
        _order = await fetchOrderById(_supabase, orderId!, buyerId: myId);
        if (_order != null && _order!.needsBuyerPayment) {
          await _reconcileOpenCheckout(orderId!);
        }
        if (_order == null) {
          _errorMessage = 'Order not found.';
          _paymentGroup = [];
        } else {
          await _loadPaymentGroup(myId);
        }
        if (_order != null && !_order!.needsBuyerPayment) {
          _isConfirmingPayment = false;
          if (_order!.isFailedCheckout) {
            _unsuccessfulOutcome = _order!.isExpiredCheckout
                ? 'expired'
                : 'failed';
          }
        }
        await _maybeLoadDeliveryPin();
      } else {
        _orders = await fetchOrdersForBuyer(_supabase, myId);
        if (_orders.every((o) => !o.needsBuyerPayment)) {
          _isConfirmingPayment = false;
        }
      }
      await _loadMyReviews(myId);
    } catch (e) {
      debugPrint('BuyerOrdersController.load error: $e');
      _errorMessage = 'Unable to load orders.';
    } finally {
      _isLoading = false;
      _notify();
    }
  }

  Future<String?> setAddress(String addressId) async {
    final id = orderId ?? _order?.id;
    if (id == null) return 'Order not found.';
    _isSavingAddress = true;
    _notify();
    try {
      final book = await AddressService(_supabase).listMine();
      AddressModel? saved;
      for (final row in book) {
        if (row.id == addressId) {
          saved = row;
          break;
        }
      }
      if (saved == null) return 'Address not found.';
      if (!saved.hasValidPhoneContact) {
        return 'Enter a valid 11-digit mobile number starting with 09. '
            'Edit this delivery address and try again.';
      }
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
      await load(showSpinner: false);
      return null;
    } catch (e) {
      debugPrint('BuyerOrdersController.setAddress error: $e');
      return 'Could not save that address.';
    } finally {
      _isSavingAddress = false;
      _notify();
    }
  }

  Future<PaymongoCheckoutResult> startPaymongoCheckout(
    String payOrderId, {
    required String channel,
  }) async {
    if (_isStartingPayment) {
      return const PaymongoCheckoutResult(
        success: false,
        error: 'Payment is already starting.',
      );
    }
    _isStartingPayment = true;
    _notify();
    try {
      final result = await createPaymongoCheckout(
        _supabase,
        orderId: payOrderId,
        channel: channel,
      );
      if (result.alreadyPaid) {
        _isConfirmingPayment = false;
        await load(showSpinner: false);
        return result;
      }
      if (result.success && result.checkoutUrl != null) {
        _isConfirmingPayment = true;
      }
      return result;
    } finally {
      _isStartingPayment = false;
      _notify();
    }
  }

  Future<void> handlePaymongoAppReturn({required bool cancelled}) async {
    _returnPoll?.cancel();
    final id = orderId ?? _order?.id;
    if (id == null || id.isEmpty) return;

    _isConfirmingPayment = true;
    _unsuccessfulOutcome = null;
    _notify();

    final reconciled = await reconcilePaymongoCheckout(_supabase, orderId: id);
    await load(showSpinner: false);
    if (_disposed) return;

    if (reconciled.isPaid) {
      _isConfirmingPayment = false;
      _unsuccessfulOutcome = null;
      _notify();
      return;
    }
    if (reconciled.isUnsuccessful || _order?.isFailedCheckout == true) {
      _isConfirmingPayment = false;
      _unsuccessfulOutcome =
          reconciled.isExpired || (_order?.isExpiredCheckout ?? false)
          ? 'expired'
          : 'failed';
      _notify();
      return;
    }
    if (_order != null &&
        !_order!.isPaymentPending &&
        !_order!.isFailedCheckout) {
      _isConfirmingPayment = false;
      _unsuccessfulOutcome = null;
      _notify();
      return;
    }

    if (cancelled) {
      _isConfirmingPayment = false;
      _unsuccessfulOutcome = null;
      _notify();
      await abandonUnpaidCheckout(id);
      return;
    }

    _isConfirmingPayment = true;
    _notify();
    var attempts = 0;
    _returnPoll = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (_disposed) {
        timer.cancel();
        return;
      }
      if (attempts >= 10) {
        timer.cancel();
        _isConfirmingPayment = false;
        _notify();
        return;
      }
      attempts += 1;
      unawaited(_pollReconcile(id, timer));
    });
  }

  Future<void> _refreshAfterResume() async {
    await load(showSpinner: false);
    if (_disposed || orderId == null) return;
    if (_isConfirmingPayment && _order?.needsBuyerPayment == true) {
      await handlePaymongoAppReturn(cancelled: false);
    }
  }

  Future<void> _loadPaymentGroup(String buyerId) async {
    final current = _order;
    final groupId = current?.checkoutGroupId;
    if (current == null) {
      _paymentGroup = [];
      return;
    }
    if (groupId == null || groupId.isEmpty) {
      _paymentGroup = [current];
      return;
    }
    try {
      final group = await fetchOrdersForCheckoutGroup(
        _supabase,
        groupId,
        buyerId: buyerId,
      );
      _paymentGroup = group.isEmpty ? [current] : group;
    } catch (e) {
      debugPrint('BuyerOrdersController._loadPaymentGroup error: $e');
      _paymentGroup = [current];
    }
  }

  Future<void> _reconcileOpenCheckout(String id) async {
    final reconciled = await reconcilePaymongoCheckout(_supabase, orderId: id);
    if (_disposed) return;
    if (reconciled.isPending && _order?.needsBuyerPayment == true) {
      return;
    }
    _order = await fetchOrderById(_supabase, id, buyerId: _auth.user?.id);
  }

  Future<void> _pollReconcile(String id, Timer timer) async {
    final reconciled = await reconcilePaymongoCheckout(_supabase, orderId: id);
    await load(showSpinner: false);
    if (_disposed) {
      timer.cancel();
      return;
    }
    if (reconciled.isPaid ||
        reconciled.isUnsuccessful ||
        _order == null ||
        !_order!.isPaymentPending ||
        _order!.isFailedCheckout) {
      _isConfirmingPayment = false;
      if (reconciled.isUnsuccessful || (_order?.isFailedCheckout ?? false)) {
        _unsuccessfulOutcome = reconciled.isExpired ? 'expired' : 'failed';
      }
      timer.cancel();
      _notify();
    }
  }

  Future<String?> abandonUnpaidCheckout(String payOrderId) async {
    if (_isAbandoning) return null;
    _isAbandoning = true;
    _notify();
    try {
      final rpcRes = await _supabase.client.rpc(
        'abandon_unpaid_checkout',
        params: {'p_order_id': payOrderId},
      );
      if (!supabaseRpcSuccess(rpcRes)) {
        return supabaseRpcError(
          rpcRes,
          fallback: 'Could not cancel this checkout.',
        );
      }
      _isConfirmingPayment = false;
      await load(showSpinner: false);
      _unsuccessfulOutcome = null;
      return null;
    } catch (e) {
      debugPrint('BuyerOrdersController.abandonUnpaidCheckout error: $e');
      return 'Could not cancel this checkout.';
    } finally {
      _isAbandoning = false;
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

  Future<void> _maybeLoadDeliveryPin() async {
    final order = _order;
    if (order == null || order.shipment?.pinAvailable != true) {
      _deliveryPin = null;
      return;
    }
    try {
      final rpcRes = await _supabase.client.rpc(
        'get_my_delivery_pin',
        params: {'p_order_id': order.id},
      );
      if (supabaseRpcSuccess(rpcRes)) {
        _deliveryPin = supabaseRpcMap(rpcRes)?['pin']?.toString();
      } else {
        _deliveryPin = null;
      }
    } catch (e) {
      debugPrint('get_my_delivery_pin error: $e');
      _deliveryPin = null;
    }
  }

  Future<String?> confirmDelivery() async {
    final id = orderId ?? _order?.id;
    if (id == null) return 'Order not found.';
    if (_isUpdatingDelivery) return null;
    _isUpdatingDelivery = true;
    _notify();
    try {
      final rpcRes = await _supabase.client.rpc(
        'confirm_delivery',
        params: {'p_order_id': id},
      );
      if (!supabaseRpcSuccess(rpcRes)) {
        return supabaseRpcError(
          rpcRes,
          fallback: 'Could not confirm this delivery.',
        );
      }
      await load(showSpinner: false);
      return null;
    } catch (e) {
      debugPrint('confirm_delivery error: $e');
      return 'Could not confirm this delivery.';
    } finally {
      _isUpdatingDelivery = false;
      _notify();
    }
  }

  Future<String?> confirmReturnHandedOff() async {
    final id = orderId ?? _order?.id;
    if (id == null) return 'Order not found.';
    if (_isUpdatingDelivery) return null;
    _isUpdatingDelivery = true;
    _notify();
    try {
      final rpcRes = await _supabase.client.rpc(
        'confirm_return_handed_off',
        params: {'p_order_id': id},
      );
      if (!supabaseRpcSuccess(rpcRes)) {
        return supabaseRpcError(
          rpcRes,
          fallback: 'Could not record the handoff.',
        );
      }
      await load(showSpinner: false);
      return null;
    } catch (e) {
      debugPrint('confirm_return_handed_off error: $e');
      return 'Could not record the handoff.';
    } finally {
      _isUpdatingDelivery = false;
      _notify();
    }
  }

  Future<String?> reportDeliveryProblem({
    required String reason,
    String? details,
  }) async {
    final id = orderId ?? _order?.id;
    if (id == null) return 'Order not found.';
    if (_isUpdatingDelivery) return null;
    _isUpdatingDelivery = true;
    _notify();
    try {
      final rpcRes = await _supabase.client.rpc(
        'report_delivery_problem',
        params: {'p_order_id': id, 'p_reason': reason, 'p_details': details},
      );
      if (!supabaseRpcSuccess(rpcRes)) {
        return supabaseRpcError(
          rpcRes,
          fallback: 'Could not report this problem.',
        );
      }
      await load(showSpinner: false);
      return null;
    } catch (e) {
      debugPrint('report_delivery_problem error: $e');
      return 'Could not report this problem.';
    } finally {
      _isUpdatingDelivery = false;
      _notify();
    }
  }

  /// Opens the device dialer for the local rider assigned to this buyer's
  /// active delivery. RLS protects the order/shipment retrieval; this extra
  /// state check prevents stale screens from exposing an inactive contact.
  Future<String?> callRider() => _openRiderContact(scheme: 'tel');

  /// Opens the device SMS composer without sending a message automatically.
  Future<String?> messageRider() => _openRiderContact(scheme: 'sms');

  /// Opens a courier's official tracking page when the backend identifies a
  /// supported courier. Unknown couriers are left without a fabricated URL.
  Future<String?> trackCourier() async {
    final order = _order;
    final tracking = order?.trackingNumber?.trim();
    if (tracking == null || tracking.isEmpty) {
      return 'Tracking number unavailable.';
    }
    final courier = order?.courier?.trim().toLowerCase() ?? '';
    final encoded = Uri.encodeComponent(tracking);
    final url = courier.contains('j&t') || courier.contains('jnt')
        ? Uri.parse(
            'https://www.jtexpress.ph/index.php/track/track.html?waybillNo=$encoded',
          )
        : courier.contains('ninja')
        ? Uri.parse('https://www.ninjavan.co/en-ph/tracking?id=$encoded')
        : courier.contains('lbc')
        ? Uri.parse('https://www.lbcexpress.com/track?tracking_no=$encoded')
        : null;
    if (url == null) return 'Tracking link unavailable for this courier.';
    try {
      final opened = await launchUrl(url, mode: LaunchMode.externalApplication);
      return opened ? null : 'Unable to open the courier tracking page.';
    } catch (e) {
      debugPrint('BuyerOrdersController.trackCourier error: $e');
      return 'Unable to open the courier tracking page.';
    }
  }

  Future<String?> _openRiderContact({required String scheme}) async {
    final shipment = _order?.shipment;
    if (shipment?.isRiderContactVisibleToBuyer != true) {
      return 'Rider contact is not available for this delivery.';
    }
    final phone = normalizePhMobile(shipment?.riderPhone);
    if (phone == null) return 'Contact number unavailable.';

    try {
      final opened = await launchUrl(
        Uri.parse('$scheme:$phone'),
        mode: LaunchMode.externalApplication,
      );
      return opened
          ? null
          : 'Unable to open your ${scheme == 'tel' ? 'phone app' : 'messaging app'}.';
    } catch (e) {
      debugPrint('BuyerOrdersController._openRiderContact error: $e');
      return 'Unable to open your ${scheme == 'tel' ? 'phone app' : 'messaging app'}.';
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
          ? 'buyer-order-$orderId'
          : 'buyer-orders-$myId';
      _channel = _supabase.client
          .channel(channelName)
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'orders',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: orderId != null ? 'order_id' : 'buyer_id',
              value: orderId ?? myId,
            ),
            callback: (_) => unawaited(load(showSpinner: false)),
          )
          .subscribe();
    } catch (e) {
      debugPrint('BuyerOrdersController realtime error: $e');
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _returnPoll?.cancel();
    _lifecycle?.dispose();
    final channel = _channel;
    _channel = null;
    if (channel != null) {
      unawaited(_supabase.client.removeChannel(channel));
    }
    super.dispose();
  }
}
