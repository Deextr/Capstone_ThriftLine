import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../models/address_model.dart';
import '../../../../providers/cart_provider.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../../profile/data/address_service.dart';
import '../../controllers/buyer_orders_controller.dart';
import '../../../../widgets/empty_state.dart';
import '../widgets/payment_checkout_body.dart';

class PaymentProofScreen extends StatefulWidget {
  const PaymentProofScreen({super.key, required this.orderId});

  final String orderId;

  @override
  State<PaymentProofScreen> createState() => _PaymentProofScreenState();
}

class _PaymentProofScreenState extends State<PaymentProofScreen> {
  var _didOpenPaidConfirmation = false;
  var _didHandleReturn = false;
  String? _selectedChannel;

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
              'We could not load this order. Check your connection and try again.',
          onRetry: controller.load,
        ),
      );
    }

    final pending = order.isPaymentPending;
    final returnUri = GoRouterState.of(context).uri;
    final returned = returnUri.queryParameters['returned'] == '1';
    final failed = order.isFailedCheckout || controller.isExpiredPayment;
    final confirming = pending && !failed && controller.isConfirmingPayment;
    _scheduleReturnHandling(returned || confirming);
    _schedulePaidConfirmation(pending, failed);

    return PopScope(
      canPop: !pending,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !pending) return;
        _leavePendingCheckout(controller);
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
                : pending
                ? 'Complete payment'
                : 'Payment Successful',
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              if (pending) {
                _leavePendingCheckout(controller);
                return;
              }
              if (failed) {
                context.go(RouteNames.cart);
                return;
              }
              context.go(RouteNames.orderConfirmFor(widget.orderId));
            },
          ),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppConstants.spacingMd),
            child: failed
                ? _FailedPaymentBody(
                    channel: _selectedChannel,
                    expired: controller.isExpiredPayment,
                    onReturnToCart: () async {
                      await context.read<CartProvider>().refresh();
                      if (context.mounted) {
                        context.go(RouteNames.cart);
                      }
                    },
                    onTryAgain: () async {
                      await context.read<CartProvider>().refresh();
                      if (context.mounted) {
                        context.go(RouteNames.cart);
                      }
                    },
                  )
                : pending
                ? PaymentCheckoutBody(
                    order: order,
                    groupOrders: controller.paymentGroup,
                    paymentDueAt: order.paymentDueAt,
                    windowOpen: order.isPaymentWindowOpen,
                    confirming: confirming,
                    selectedChannel: _selectedChannel,
                    isAbandoning: controller.isAbandoning,
                    isSavingAddress: controller.isSavingAddress,
                    returnLabel: (order.auctionId ?? '').isNotEmpty
                        ? 'Cancel payment'
                        : 'Return to cart',
                    onSelectChannel: (channel) {
                      setState(() => _selectedChannel = channel);
                    },
                    onChangeAddress: () => _changeAddress(controller),
                    onReturnToCart: confirming
                        ? null
                        : () => unawaited(_returnToCart(controller)),
                  )
                : _PaidPaymentBody(
                    orderNumber: order.orderNumber,
                    channel: _selectedChannel,
                    onViewOrder: () =>
                        context.go(RouteNames.orderConfirmFor(widget.orderId)),
                  ),
          ),
        ),
      ),
    );
  }

  Future<void> _leavePendingCheckout(BuyerOrdersController controller) async {
    final isAuction = (controller.order?.auctionId ?? '').isNotEmpty;
    if (isAuction) {
      context.go(RouteNames.buyerHome);
      return;
    }

    final cancelAndReturn = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave checkout?'),
        content: const Text(
          'Do you want to cancel this checkout and return items to your cart, or keep it pending?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep pending'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Return to cart'),
          ),
        ],
      ),
    );

    if (!mounted || cancelAndReturn == null) return;
    if (cancelAndReturn) {
      await _returnToCart(controller);
    } else {
      context.go(RouteNames.buyerHome);
    }
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

  Future<void> _returnToCart(BuyerOrdersController controller) async {
    final isAuction = (controller.order?.auctionId ?? '').isNotEmpty;
    final error = await controller.abandonUnpaidCheckout(widget.orderId);
    if (!mounted) return;
    if (!isAuction) {
      await context.read<CartProvider>().refresh();
      if (!mounted) return;
    }
    if (error != null) {
      showThriftSnackBar(context, error, isError: true);
    } else {
      showThriftSnackBar(
        context,
        'Checkout cancelled. Items returned to your cart.',
      );
    }
    context.go(isAuction ? RouteNames.buyerHome : RouteNames.cart);
  }

  void _scheduleReturnHandling(bool returned) {
    if (!returned || _didHandleReturn) return;
    _didHandleReturn = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        context.read<BuyerOrdersController>().handlePaymongoAppReturn(),
      );
    });
  }

  void _schedulePaidConfirmation(bool pending, bool failed) {
    if (pending || failed || _didOpenPaidConfirmation) return;
    _didOpenPaidConfirmation = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.go(RouteNames.orderConfirmFor(widget.orderId));
    });
  }
}

class _FailedPaymentBody extends StatelessWidget {
  const _FailedPaymentBody({
    required this.channel,
    required this.expired,
    required this.onReturnToCart,
    required this.onTryAgain,
  });

  final String? channel;
  final bool expired;
  final VoidCallback onReturnToCart;
  final VoidCallback onTryAgain;

  @override
  Widget build(BuildContext context) {
    final method = channel == 'gcash'
        ? 'GCash payment'
        : channel == 'card'
        ? 'card payment'
        : 'payment';
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
          expired ? 'Payment Expired' : 'Payment Failed',
          style: AppTypography.display,
        ),
        const SizedBox(height: 8),
        Text(
          expired
              ? 'Payment expired. Your order was not completed.\nNo purchase was finalized.\n\nThe item is still in your cart.'
              : 'Your $method was not completed.\nNo purchase was finalized.\n\nThe item is still in your cart.',
          style: AppTypography.body,
          textAlign: TextAlign.center,
        ),
        const Spacer(),
        ThriftButton(label: 'Return to Cart', onPressed: onReturnToCart),
        const SizedBox(height: 12),
        ThriftButton(
          label: 'Try Again',
          variant: ThriftButtonVariant.outline,
          onPressed: onTryAgain,
        ),
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
