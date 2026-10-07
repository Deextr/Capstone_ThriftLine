import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/utils/supabase_errors.dart';
import '../../../core/utils/ph_phone.dart';
import '../../../core/utils/supabase_rpc.dart';
import '../../../models/address_model.dart';
import '../../../models/community_report_model.dart';
import '../../../models/order_model.dart';
import '../../../models/review_model.dart';
import '../../../providers/auth_provider.dart';
import '../../profile/data/address_service.dart';
import '../../trust_safety/data/report_query.dart';
import '../../trust_safety/data/review_query.dart';
import '../data/checkout_payment_group.dart';
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
  Map<String, CommunityReportModel> _myReportsByOrderId = {};
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
  int _returnGeneration = 0;
  int _loadGeneration = 0;
  bool _disposed = false;
  bool _skipPaymentReconcileOnce = false;
  bool _checkoutClosed = false;
  bool _awaitingPaymongoReturn = false;
  int _returnReconcileDepth = 0;
  Timer? _returnReconcileTimer;

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
  CommunityReportModel? reportForOrder(String orderId) =>
      _myReportsByOrderId[orderId];
  bool get isLoading => _isLoading;
  bool get isSavingAddress => _isSavingAddress;
  bool get isStartingPayment => _isStartingPayment;
  bool get isConfirmingPayment => _isConfirmingPayment;
  bool get awaitingPaymongoReturn => _awaitingPaymongoReturn;
  bool get isAbandoning => _isAbandoning;
  bool get checkoutClosed => _checkoutClosed;
  bool get isUpdatingDelivery => _isUpdatingDelivery;
  String? get errorMessage => _errorMessage;
  String? get deliveryPin => _deliveryPin;
  bool get isExpiredPayment =>
      _unsuccessfulOutcome == 'expired' || (_order?.isExpiredCheckout ?? false);

  bool get showsPaymentFailureUi =>
      !_checkoutClosed &&
      (isExpiredPayment ||
          _unsuccessfulOutcome == 'failed' ||
          checkoutPaymentGroupHasFailure(paymentGroup) ||
          (_order?.isPaymongoPaymentFailure ?? false));

  /// Combined checkout is paid only when every seller order in the group is paid.
  bool get isPaymentGroupPaid => isCheckoutPaymentGroupPaid(
    paymentGroup.isNotEmpty
        ? paymentGroup
        : (_order == null ? const <OrderModel>[] : [_order!]),
  );

  bool get paymentGroupNeedsPayment => checkoutPaymentGroupNeedsPayment(
    paymentGroup.isNotEmpty
        ? paymentGroup
        : (_order == null ? const <OrderModel>[] : [_order!]),
  );

  Future<void> load({bool showSpinner = true}) async {
    final myId = _auth.user?.id;
    final generation = ++_loadGeneration;
    if (myId == null) {
      _orders = [];
      _order = null;
      _paymentGroup = [];
      _myReviews = {};
      _myReportsByOrderId = {};
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
      if (generation != _loadGeneration) return;
      if (orderId != null) {
        final fetched = await fetchOrderById(
          _supabase,
          orderId!,
          buyerId: myId,
        );
        if (generation != _loadGeneration) return;
        _order = fetched;
        if (_order != null && _order!.needsBuyerPayment) {
          if (_skipPaymentReconcileOnce) {
            _skipPaymentReconcileOnce = false;
          } else if (_returnReconcileDepth == 0) {
            await _reconcileOpenCheckout(orderId!);
            if (generation != _loadGeneration) return;
          }
        }
        if (_order == null) {
          _errorMessage = 'Order not found.';
          _paymentGroup = [];
        } else {
          await _loadPaymentGroup(myId);
        }
        if (generation != _loadGeneration) return;
        if (_order != null && !_order!.needsBuyerPayment) {
          _isConfirmingPayment = false;
          if (!_checkoutClosed && _order!.isPaymongoPaymentFailure) {
            _unsuccessfulOutcome = _order!.isExpiredCheckout
                ? 'expired'
                : 'failed';
          }
        }
        await _maybeLoadDeliveryPin();
      } else {
        _orders = await fetchOrdersForBuyer(_supabase, myId);
        if (generation != _loadGeneration) return;
        if (_orders.every((o) => !o.needsBuyerPayment)) {
          _isConfirmingPayment = false;
        }
      }
      await _loadMyReviews(myId);
      await _loadMyReportsForOrders(myId);
    } catch (e) {
      debugPrint('BuyerOrdersController.load error: $e');
      if (generation == _loadGeneration) {
        _errorMessage = userFacingOrderLoadError(
          e,
          fallback: 'Unable to load orders. Please try again.',
        );
      }
    } finally {
      if (generation == _loadGeneration) {
        _isLoading = false;
        _notify();
      }
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
    final current = _order;
    if (current != null && !current.hasValidDeliveryAddress) {
      return const PaymongoCheckoutResult(
        success: false,
        error: 'Add a delivery address before paying.',
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
        _awaitingPaymongoReturn = false;
        _isConfirmingPayment = false;
        await load(showSpinner: false);
        return result;
      }
      return result;
    } finally {
      _isStartingPayment = false;
      _notify();
    }
  }

  /// Call after PayMongo hosted checkout opens in the external browser.
  void markPaymongoBrowserOpened() {
    _awaitingPaymongoReturn = true;
    _isConfirmingPayment = true;
    _unsuccessfulOutcome = null;
    _notify();
  }

  void clearPaymongoAwaiting() {
    _awaitingPaymongoReturn = false;
    _isConfirmingPayment = false;
    _notify();
  }

  Future<PaymongoAppReturnResult> handlePaymongoAppReturn({
    String? returnStatus,
    bool fromReturnRedirect = false,
    bool hostedCheckoutOpened = false,
  }) async {
    final id = orderId ?? _order?.id;
    if (id == null || id.isEmpty) return PaymongoAppReturnResult.pending;
    final generation = ++_returnGeneration;
    _returnReconcileTimer?.cancel();
    _returnReconcileTimer = null;

    final fromHostedCheckout =
        _awaitingPaymongoReturn || hostedCheckoutOpened || fromReturnRedirect;

    if (!fromHostedCheckout) {
      return PaymongoAppReturnResult.pending;
    }

    _isConfirmingPayment = true;
    _unsuccessfulOutcome = null;
    _notify();

    _returnReconcileDepth++;
    try {
      const retryDelaysMs = <int>[0, 400, 900, 1500];
      for (var attempt = 0; attempt < retryDelaysMs.length; attempt++) {
        if (retryDelaysMs[attempt] > 0) {
          await Future<void>.delayed(
            Duration(milliseconds: retryDelaysMs[attempt]),
          );
        }
        if (_disposed || generation != _returnGeneration) {
          return PaymongoAppReturnResult.pending;
        }

        final started = DateTime.now();
        if (kDebugMode) {
          debugPrint('[Payment] reconcile attempt ${attempt + 1} order=$id');
        }

        final reconciled = await reconcilePaymongoCheckout(
          _supabase,
          orderId: id,
        );
        await _refreshOrderAfterReconcile(id);
        if (_disposed || generation != _returnGeneration) {
          return PaymongoAppReturnResult.pending;
        }

        if (kDebugMode) {
          debugPrint(
            '[Payment] reconcile outcome=${reconciled.outcome} '
            'elapsed=${DateTime.now().difference(started).inMilliseconds}ms',
          );
        }

        if (_isReconcilePaid(reconciled)) {
          _awaitingPaymongoReturn = false;
          _isConfirmingPayment = false;
          _unsuccessfulOutcome = null;
          _notify();
          return PaymongoAppReturnResult.paid;
        }

        if (reconciled.isUnsuccessful ||
            checkoutPaymentGroupHasFailure(paymentGroup) ||
            (_order?.isPaymongoPaymentFailure ?? false)) {
          _awaitingPaymongoReturn = false;
          return _completePaymongoFailure(
            orderId: id,
            generation: generation,
            clientOutcome: reconciled.isExpired ? 'expired' : 'failed',
            showFailureUiFirst: true,
          );
        }
      }
    } finally {
      _returnReconcileDepth--;
    }

    if (_disposed || generation != _returnGeneration) {
      return PaymongoAppReturnResult.pending;
    }

    // Keep Confirming Payment visible while PayMongo/webhook catch up.
    _isConfirmingPayment = true;
    _awaitingPaymongoReturn = true;
    _notify();
    _scheduleReturnReconcileFollowUp(orderId: id, generation: generation);
    return PaymongoAppReturnResult.pending;
  }

  bool _isReconcilePaid(PaymongoReconcileResult reconciled) {
    return reconciled.isPaid ||
        isPaymentGroupPaid ||
        (_order?.isPaidCheckout ?? false);
  }

  void _scheduleReturnReconcileFollowUp({
    required String orderId,
    required int generation,
  }) {
    _returnReconcileTimer?.cancel();
    var followUp = 0;
    _returnReconcileTimer = Timer.periodic(const Duration(seconds: 3), (
      timer,
    ) async {
      followUp++;
      if (_disposed ||
          generation != _returnGeneration ||
          followUp > 20 ||
          !_awaitingPaymongoReturn) {
        timer.cancel();
        _returnReconcileTimer = null;
        return;
      }

      final reconciled = await reconcilePaymongoCheckout(
        _supabase,
        orderId: orderId,
      );
      await _refreshOrderAfterReconcile(orderId);
      if (_disposed || generation != _returnGeneration) {
        timer.cancel();
        _returnReconcileTimer = null;
        return;
      }

      if (_isReconcilePaid(reconciled)) {
        timer.cancel();
        _returnReconcileTimer = null;
        _awaitingPaymongoReturn = false;
        _isConfirmingPayment = false;
        _unsuccessfulOutcome = null;
        _notify();
        return;
      }

      if (reconciled.isUnsuccessful ||
          checkoutPaymentGroupHasFailure(paymentGroup) ||
          (_order?.isPaymongoPaymentFailure ?? false)) {
        timer.cancel();
        _returnReconcileTimer = null;
        unawaited(
          _completePaymongoFailure(
            orderId: orderId,
            generation: generation,
            clientOutcome: reconciled.isExpired ? 'expired' : 'failed',
            showFailureUiFirst: true,
          ),
        );
      }
    });
  }

  Future<void> _refreshOrderAfterReconcile(String id) async {
    final myId = _auth.user?.id;
    if (myId == null) return;
    try {
      _order = await fetchOrderById(_supabase, id, buyerId: myId);
      await _loadPaymentGroup(myId);
      _notify();
    } catch (e) {
      debugPrint('BuyerOrdersController._refreshOrderAfterReconcile error: $e');
    }
  }

  Future<PaymongoAppReturnResult> _completePaymongoFailure({
    required String orderId,
    required int generation,
    required String clientOutcome,
    bool showFailureUiFirst = false,
  }) async {
    if (_disposed || generation != _returnGeneration) {
      return PaymongoAppReturnResult.pending;
    }

    if (showFailureUiFirst) {
      _isConfirmingPayment = false;
      _unsuccessfulOutcome = clientOutcome == 'expired' ? 'expired' : 'failed';
      _notify();
    }

    if (_order == null || !_order!.isAuctionObligation) {
      final restoreCart = !(_order?.isBuyNowCheckout ?? false);
      await finalizeMyPaymongoCheckout(
        _supabase,
        orderId: orderId,
        clientOutcome: clientOutcome,
        restoreCart: restoreCart,
      );
      _skipPaymentReconcileOnce = true;
      await _refreshOrderAfterReconcile(orderId);
      if (_disposed || generation != _returnGeneration) {
        return PaymongoAppReturnResult.pending;
      }
      if (restoreCart) {
        unawaited(restoreAbandonedFixedPriceCheckouts(_supabase));
      }
    }

    _awaitingPaymongoReturn = false;
    _isConfirmingPayment = false;
    _unsuccessfulOutcome = clientOutcome == 'expired' ? 'expired' : 'failed';
    _notify();
    return PaymongoAppReturnResult.failed;
  }

  Future<void> _refreshAfterResume() async {
    if (_disposed || orderId == null) return;
    if (_awaitingPaymongoReturn) {
      if (kDebugMode) {
        debugPrint('[Payment] App resumed (controller) order=$orderId');
      }
      await handlePaymongoAppReturn(hostedCheckoutOpened: true);
      return;
    }
    await load(showSpinner: false);
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
    await _refreshOrderAfterReconcile(id);
    if (_disposed) return;
    if (_isReconcilePaid(reconciled)) {
      _awaitingPaymongoReturn = false;
      _isConfirmingPayment = false;
      _unsuccessfulOutcome = null;
      _notify();
      return;
    }
    if (reconciled.isPending && paymentGroupNeedsPayment) {
      // Hosted checkout may already be paid at PayMongo; keep confirming UI.
      if (_awaitingPaymongoReturn) {
        _isConfirmingPayment = true;
        _notify();
      }
      return;
    }
  }

  /// Buyer intentionally leaves payment (not PayMongo failure).
  Future<String?> abandonUnpaidCheckout(
    String payOrderId, {
    bool restoreCart = true,
  }) async {
    if (_isAbandoning) return null;
    _isAbandoning = true;
    _notify();
    final isAuction = (_order?.auctionId ?? '').isNotEmpty;
    final restore = restoreCart && !isAuction;
    final targetOrderId = _order?.id ?? payOrderId;
    try {
      final rpcMap = await _rpcAbandonUnpaidCheckout(
        targetOrderId,
        restoreCart: restore,
      );
      final rpcOk = supabaseRpcSuccess(rpcMap);
      if (!rpcOk) {
        debugPrint('abandonUnpaidCheckout RPC failed: $rpcMap');
        _checkoutClosed = false;
        await load(showSpinner: false);
        if (_order?.isAbandonedCheckout == true ||
            _order?.isFailedCheckout == true ||
            !(_order?.needsBuyerPayment ?? true)) {
          _isConfirmingPayment = false;
          _unsuccessfulOutcome = null;
          return null;
        }
        return supabaseRpcError(
          rpcMap,
          fallback: 'We could not close this checkout yet. Please try again.',
        );
      }
      if (rpcMap?['already_paid'] == true) {
        _checkoutClosed = false;
        await load(showSpinner: false);
        return 'This order is already paid.';
      }
      _skipPaymentReconcileOnce = true;
      _awaitingPaymongoReturn = false;
      _isConfirmingPayment = false;
      _errorMessage = null;
      _unsuccessfulOutcome = null;
      _checkoutClosed = true;
      _notify();
      await load(showSpinner: false);
      return null;
    } catch (e) {
      _checkoutClosed = false;
      if (e is PostgrestException) {
        debugPrint(
          'BuyerOrdersController.abandonUnpaidCheckout PostgrestException '
          'code=${e.code} message=${e.message} details=${e.details}',
        );
      } else {
        debugPrint('BuyerOrdersController.abandonUnpaidCheckout error: $e');
      }
      await load(showSpinner: false);
      if (_order?.isAbandonedCheckout == true ||
          _order?.isFailedCheckout == true ||
          !(_order?.needsBuyerPayment ?? true)) {
        return null;
      }
      if (e is PostgrestException) {
        final msg = e.message.trim();
        if (msg.isNotEmpty &&
            (msg.contains('Could not find the function') ||
                msg.contains('does not exist'))) {
          return 'We could not close this checkout yet. The server checkout '
              'update may be missing — apply the latest database migrations.';
        }
      }
      return 'We could not close this checkout yet. Please try again.';
    } finally {
      _isAbandoning = false;
      _notify();
    }
  }

  void clearCheckoutLeaveState() {
    _checkoutClosed = false;
  }

  Future<Map<String, dynamic>?> _rpcAbandonUnpaidCheckout(
    String payOrderId, {
    required bool restoreCart,
  }) async {
    Object? lastError;
    for (final params in [
      {'p_order_id': payOrderId, 'p_restore_cart': restoreCart},
      {'p_order_id': payOrderId},
    ]) {
      try {
        final rpcRes = await _supabase.client.rpc(
          'abandon_unpaid_checkout',
          params: params,
        );
        final map = supabaseRpcMap(rpcRes);
        if (map != null) return map;
      } catch (e) {
        lastError = e;
        debugPrint(
          'BuyerOrdersController._rpcAbandonUnpaidCheckout params=$params error: $e',
        );
      }
    }
    if (lastError != null) throw lastError!;
    return null;
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

  Future<void> _loadMyReportsForOrders(String myId) async {
    final ids = <String>{
      if (_order != null) _order!.id,
      for (final order in _orders) order.id,
    };
    _myReportsByOrderId = await fetchMyReportsForOrders(_supabase, myId, ids);
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
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'reports',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'reporter_id',
              value: myId,
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
    _returnGeneration++;
    _returnReconcileTimer?.cancel();
    _returnReconcileTimer = null;
    _lifecycle?.dispose();
    final channel = _channel;
    _channel = null;
    if (channel != null) {
      unawaited(_supabase.client.removeChannel(channel));
    }
    super.dispose();
  }
}
