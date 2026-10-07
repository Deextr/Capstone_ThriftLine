import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/paymongo_return_coordinator.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../models/address_model.dart';
import '../../../../models/order_model.dart';
import '../../../../providers/cart_provider.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../../profile/data/address_service.dart';
import '../../controllers/buyer_orders_controller.dart';
import '../../data/paymongo_checkout.dart';
import '../../data/order_query.dart';
import '../../domain/checkout_origin.dart';
import '../../domain/payment_checkout_context.dart';
import '../../../../widgets/empty_state.dart';
import '../widgets/payment_checkout_body.dart';

class PaymentProofScreen extends StatefulWidget {
  const PaymentProofScreen({super.key, required this.orderId});

  final String orderId;

  @override
  State<PaymentProofScreen> createState() => _PaymentProofScreenState();
}

class _PaymentProofScreenState extends State<PaymentProofScreen>
    with WidgetsBindingObserver {
  var _didOpenPaidConfirmation = false;
  String? _handledPaymongoReturnQuery;
  String? _selectedChannel;

  PaymongoReturnCoordinator? _paymongoReturn;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final coord = context.read<PaymongoReturnCoordinator>();
    if (!identical(_paymongoReturn, coord)) {
      _paymongoReturn?.removeListener(_onPaymongoCoordinatorChanged);
      _paymongoReturn = coord..addListener(_onPaymongoCoordinatorChanged);
    }
  }

  @override
  void dispose() {
    _paymongoReturn?.removeListener(_onPaymongoCoordinatorChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onPaymongoCoordinatorChanged() {
    if (!mounted) return;
    final pending = _paymongoReturn?.pending;
    if (pending != null && pending.orderId == widget.orderId) {
      _runPaymongoReturnReconciliation(
        returnStatus: pending.cancelled
            ? 'cancel'
            : pending.expired
            ? 'expired'
            : pending.failed
            ? 'failed'
            : 'success',
        fromReturnRedirect: true,
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _onAppResumedFromPaymongo();
    }
  }

  void _onAppResumedFromPaymongo() {
    if (!mounted) return;
    final coord = context.read<PaymongoReturnCoordinator>();
    final controller = context.read<BuyerOrdersController>();
    if (!controller.awaitingPaymongoReturn &&
        !coord.isAwaitingCheckout(widget.orderId)) {
      return;
    }
    assert(() {
      debugPrint('[Payment] App resumed (payment screen) order=${widget.orderId}');
      return true;
    }());
    final returnUri = GoRouterState.of(context).uri;
    final status = returnUri.queryParameters['returned'] == '1'
        ? returnUri.queryParameters['status']
        : null;
    _runPaymongoReturnReconciliation(
      returnStatus: status,
      fromReturnRedirect: returnUri.queryParameters['returned'] == '1',
    );
  }

  CheckoutOrigin _origin(OrderModel? order) {
    return resolveCheckoutOrigin(
      uri: GoRouterState.of(context).uri,
      order: order,
    );
  }

  String? _productIdForReturn(OrderModel? order) {
    return resolveCheckoutProductId(
      uri: GoRouterState.of(context).uri,
      order: order,
    );
  }

  bool _paymentInProgress(BuyerOrdersController controller) {
    return controller.isConfirmingPayment || controller.isStartingPayment;
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<BuyerOrdersController>();
    if (controller.isLoading && controller.order == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Complete payment')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: AppColors.primary),
              const SizedBox(height: 16),
              Text('Loading your order…', style: AppTypography.body),
            ],
          ),
        ),
      );
    }
    final order = controller.order;
    if (order == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Complete payment'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go(RouteNames.cart),
          ),
        ),
        body: ErrorState(
          message:
              controller.errorMessage ??
              'We could not load this order. Please try again.',
          onRetry: controller.load,
        ),
      );
    }

    final origin = _origin(order);
    final isAuction = (order.auctionId ?? '').isNotEmpty;
    final awaiting = order.needsBuyerPayment;
    final paid = order.isPaidCheckout;
    final closing = controller.isAbandoning || controller.checkoutClosed;
    final returnUri = GoRouterState.of(context).uri;
    final returned = returnUri.queryParameters['returned'] == '1';
    final returnStatus = returnUri.queryParameters['status'];
    final failed = controller.showsPaymentFailureUi;
    final confirming =
        awaiting && !failed && !closing && controller.isConfirmingPayment;
    _schedulePaymongoReturnHandling(returned, returnStatus);
    _schedulePaidConfirmation(paid: paid, failed: failed, closing: closing);

    if (order.isAbandonedCheckout && !closing && !controller.isAbandoning) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_navigateAfterCheckoutExit(origin: origin, order: order));
      });
      return Scaffold(
        appBar: AppBar(title: const Text('Complete payment')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: AppColors.primary),
              const SizedBox(height: 16),
              Text('Closing checkout…', style: AppTypography.body),
            ],
          ),
        ),
      );
    }

    if (closing) {
      return Scaffold(
        appBar: AppBar(title: const Text('Complete payment')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: AppColors.primary),
              const SizedBox(height: 16),
              Text('Closing checkout…', style: AppTypography.body),
            ],
          ),
        ),
      );
    }

    return PopScope(
      canPop: !awaiting || isAuction,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !awaiting || isAuction) return;
        _onBackFromPendingPayment(controller, order);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            failed
                ? (controller.isExpiredPayment
                      ? 'Payment Expired'
                      : 'Payment Failed')
                : confirming
                ? 'Confirming your payment...'
                : awaiting
                ? 'Complete payment'
                : paid
                ? 'Payment Successful'
                : 'Complete payment',
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => _onAppBarBack(
              controller,
              order,
              pending: awaiting,
              failed: failed,
              isAuction: isAuction,
            ),
          ),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppConstants.spacingMd),
            child: failed
                ? _FailedPaymentBody(
                    expired: controller.isExpiredPayment,
                    origin: origin,
                    productId: _productIdForReturn(order),
                    onDismiss: () => _goAfterFailure(origin, order),
                    onTryAgain: () => _goAfterFailure(origin, order),
                  )
                : awaiting
                ? PaymentCheckoutBody(
                    order: order,
                    payOrderId: widget.orderId,
                    groupOrders: controller.paymentGroup,
                    paymentDueAt: order.paymentDueAt,
                    windowOpen: order.isPaymentWindowOpen,
                    confirming: confirming,
                    selectedChannel: _selectedChannel,
                    isAbandoning: controller.isAbandoning,
                    isSavingAddress: controller.isSavingAddress,
                    onSelectChannel: (channel) {
                      setState(() => _selectedChannel = channel);
                    },
                    onChangeAddress: () => _changeAddress(controller),
                  )
                : paid
                ? _PaidPaymentBody(
                    orderNumber: order.orderNumber,
                    channel: _selectedChannel,
                    onViewOrder: () =>
                        context.go(RouteNames.orderConfirmFor(widget.orderId)),
                  )
                : Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(
                          color: AppColors.primary,
                        ),
                        const SizedBox(height: 16),
                        Text('Loading your order…', style: AppTypography.body),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  void _onAppBarBack(
    BuyerOrdersController controller,
    OrderModel order, {
    required bool pending,
    required bool failed,
    required bool isAuction,
  }) {
    if (isAuction) {
      context.go(RouteNames.buyerHome);
      return;
    }
    if (pending && !failed) {
      _onBackFromPendingPayment(controller, order);
      return;
    }
    if (failed) {
      _goAfterFailure(_origin(order), order);
      return;
    }
    context.go(RouteNames.orderConfirmFor(widget.orderId));
  }

  Future<void> _onBackFromPendingPayment(
    BuyerOrdersController controller,
    OrderModel order,
  ) async {
    if (_paymentInProgress(controller)) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Payment in progress'),
          content: const Text(
            'We are still confirming your payment. Please wait a moment.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final origin = _origin(order);
    final leave = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave payment?'),
        content: Text(
          origin == CheckoutOrigin.cart
              ? 'Your payment has not been completed. You can return and try again later. Items will stay in your cart.'
              : 'Your payment has not been completed. You can return and try again later.',
        ),
        actionsAlignment: MainAxisAlignment.end,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Leave checkout'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Continue to payment'),
          ),
        ],
      ),
    );

    if (!mounted || leave != true) return;
    await _leaveCheckout(
      controller: controller,
      origin: _origin(order),
      order: order,
    );
  }

  Future<void> _leaveCheckout({
    required BuyerOrdersController controller,
    required CheckoutOrigin origin,
    required OrderModel order,
  }) async {
    final restoreCart = origin.restoreCartOnAbandon;
    final error = await controller.abandonUnpaidCheckout(
      widget.orderId,
      restoreCart: restoreCart,
    );
    if (!mounted) return;

    if (error != null) {
      controller.clearCheckoutLeaveState();
      showThriftSnackBar(context, error, isError: true);
      return;
    }

    final supabase = context.read<SupabaseService>();
    if (restoreCart) {
      await restoreAbandonedFixedPriceCheckouts(supabase);
      if (!mounted) return;
    }
    await context.read<CartProvider>().refresh();
    if (!mounted) return;

    if (restoreCart) {
      showThriftSnackBar(
        context,
        'Checkout cancelled. Items returned to your cart.',
      );
    }

    if (!mounted) return;
    await _navigateAfterCheckoutExit(origin: origin, order: order);
    if (!mounted) return;
    controller.clearCheckoutLeaveState();
  }

  Future<void> _navigateAfterCheckoutExit({
    required CheckoutOrigin origin,
    required OrderModel order,
  }) async {
    if (origin == CheckoutOrigin.buyNow) {
      final productId = _productIdForReturn(order);
      if (!mounted) return;
      context.go(RouteNames.buyerHome);
      if (productId != null && productId.isNotEmpty) {
        await context.push(RouteNames.productFor(productId));
      }
      return;
    }
    if (!mounted) return;
    context.go(RouteNames.cart);
  }

  void _goAfterFailure(CheckoutOrigin origin, OrderModel order) {
    unawaited(context.read<CartProvider>().refresh());
    unawaited(_navigateAfterCheckoutExit(origin: origin, order: order));
  }

  Future<void> _changeAddress(BuyerOrdersController controller) async {
    final result = await context.push<dynamic>(
      RouteNames.addresses,
      extra: controller.order?.addressId,
    );
    if (!mounted) return;

    String? newAddressId;
    if (result is AddressModel) {
      newAddressId = result.id;
    } else {
      final supabase = context.read<SupabaseService>();
      final def = await AddressService(supabase).defaultAddress();
      newAddressId = def?.id;
    }

    if (newAddressId != null && newAddressId.isNotEmpty) {
      final error = await controller.setAddress(newAddressId);
      if (!mounted) return;
      if (error != null) {
        showThriftSnackBar(context, error, isError: true);
      } else {
        showThriftSnackBar(context, 'Delivery address updated.');
      }
    }
  }

  /// Reconcile only after PayMongo deep-link return (`returned=1`), not when Pay
  /// is clicked — otherwise `_handledPaymongoReturnQuery` blocks the real return.
  void _schedulePaymongoReturnHandling(bool returned, String? returnStatus) {
    if (!returned) return;
    final returnQuery = GoRouterState.of(context).uri.query;
    if (_handledPaymongoReturnQuery == returnQuery) return;
    _handledPaymongoReturnQuery = returnQuery;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _runPaymongoReturnReconciliation(
        returnStatus: returnStatus,
        fromReturnRedirect: true,
      );
    });
  }

  Future<void> _runPaymongoReturnReconciliation({
    required String? returnStatus,
    required bool fromReturnRedirect,
  }) async {
    if (!mounted) return;
    final coord = context.read<PaymongoReturnCoordinator>();
    final controller = context.read<BuyerOrdersController>();
    final result = await controller.handlePaymongoAppReturn(
      returnStatus: returnStatus,
      fromReturnRedirect: fromReturnRedirect,
      hostedCheckoutOpened: coord.isAwaitingCheckout(widget.orderId),
    );
    if (!mounted) return;
    if (result != PaymongoAppReturnResult.pending) {
      coord.clearCheckoutOpened();
    }
  }

  void _schedulePaidConfirmation({
    required bool paid,
    required bool failed,
    required bool closing,
  }) {
    if (!paid || failed || closing || _didOpenPaidConfirmation) return;
    _didOpenPaidConfirmation = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.go(RouteNames.orderConfirmFor(widget.orderId));
    });
  }
}

class _FailedPaymentBody extends StatelessWidget {
  const _FailedPaymentBody({
    required this.expired,
    required this.origin,
    required this.productId,
    required this.onDismiss,
    required this.onTryAgain,
  });

  final bool expired;
  final CheckoutOrigin origin;
  final String? productId;
  final VoidCallback onDismiss;
  final VoidCallback onTryAgain;

  @override
  Widget build(BuildContext context) {
    final buyNow = origin == CheckoutOrigin.buyNow;
    final dismissLabel = buyNow ? 'Back to listing' : 'Return to Cart';
    final body = expired
        ? (buyNow
              ? 'Your payment window ended before checkout completed.\nThis listing is still available if stock remains.'
              : 'Your payment window ended before checkout completed.\nYour items are still available in your Cart, subject to current stock availability.')
        : (buyNow
              ? 'Your payment was not completed.\nThis listing is still available if stock remains.'
              : 'Your payment was not completed.\nYour items are still available in your Cart, subject to current stock availability.');

    return Column(
      children: [
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.error.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.error_outline_rounded,
            size: 64,
            color: AppColors.error,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          expired ? 'Payment expired' : 'Payment unsuccessful',
          style: AppTypography.display,
        ),
        const SizedBox(height: 8),
        Text(body, style: AppTypography.body, textAlign: TextAlign.center),
        const Spacer(),
        ThriftButton(label: dismissLabel, onPressed: onDismiss),
        if (!buyNow) ...[
          const SizedBox(height: 12),
          ThriftButton(
            label: 'Try Again',
            variant: ThriftButtonVariant.outline,
            onPressed: onTryAgain,
          ),
        ],
      ],
    );
  }
}

class _PaidPaymentBody extends StatelessWidget {
  const _PaidPaymentBody({
    required this.orderNumber,
    required this.channel,
    required this.onViewOrder,
  });

  final String orderNumber;
  final String? channel;
  final VoidCallback onViewOrder;

  @override
  Widget build(BuildContext context) {
    final method = channel == 'gcash'
        ? 'GCash payment received.'
        : channel == 'card'
        ? 'Card payment received.'
        : 'Your payment has been successfully confirmed.';
    return Column(
      children: [
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_circle,
            size: 64,
            color: AppColors.success,
          ),
        ),
        const SizedBox(height: 24),
        Text('Payment Successful', style: AppTypography.display),
        const SizedBox(height: 8),
        Text(method, style: AppTypography.body, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(
          'Order #$orderNumber has been paid successfully.\nThe seller can now prepare your order.',
          style: AppTypography.caption,
          textAlign: TextAlign.center,
        ),
        const Spacer(),
        ThriftButton(label: 'View Order', onPressed: onViewOrder),
      ],
    );
  }
}
